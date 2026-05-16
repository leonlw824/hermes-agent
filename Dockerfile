FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source
FROM debian:13.4

# Disable Python stdout buffering to ensure logs are printed immediately
ENV PYTHONUNBUFFERED=1

# Store Playwright browsers outside the volume mount so the build-time
# install survives the /opt/data volume overlay at runtime.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# ---------- China mirror config ----------
# Debian apt mirror
RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources
# npm mirror (global, picked up by all npm install subprocesses)
ENV npm_config_registry=https://registry.npmmirror.com
# Playwright Chromium: download directly from Microsoft CDN
# (npmmirror.com playwright mirror is often out of date)
# uv / pip mirror
ENV UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/

# Install system dependencies in one layer, clear APT cache
# tini reaps orphaned zombie processes (MCP stdio subprocesses, git, bun, etc.)
# that would otherwise accumulate when hermes runs as PID 1. See #15012.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential curl nodejs npm python3 ripgrep ffmpeg gcc python3-dev libffi-dev procps git openssh-client docker-cli gosu tini && \
    rm -rf /var/lib/apt/lists/*

# Non-root user for runtime; UID can be overridden via HERMES_UID at runtime
RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

WORKDIR /opt/hermes

# ---------- Layer-cached dependency install ----------
# Copy only package manifests first so npm install + Playwright are cached
# unless the lockfiles themselves change.
COPY package.json package-lock.json ./
COPY web/package.json web/package-lock.json web/
COPY ui-tui/package.json ui-tui/package-lock.json ui-tui/
COPY ui-tui/packages/hermes-ink/package.json ui-tui/packages/hermes-ink/package-lock.json ui-tui/packages/hermes-ink/

RUN npm install --no-audit && \
    (cd web && npm install --no-audit) && \
    (cd ui-tui && npm install --no-audit)

RUN npx playwright install --with-deps chromium --only-shell

# ---------- Source code ----------
# .dockerignore excludes node_modules, so the installs above survive.
COPY --chown=hermes:hermes . .

# Build browser dashboard and terminal UI assets.
RUN cd web && npm run build && \
    cd ../ui-tui && npm run build && \
    rm -rf node_modules/@hermes/ink && \
    rm -rf packages/hermes-ink/node_modules && \
    cp -R packages/hermes-ink node_modules/@hermes/ink && \
    npm install --omit=dev --no-audit --prefix node_modules/@hermes/ink && \
    rm -rf node_modules/@hermes/ink/node_modules/react && \
    node --input-type=module -e "await import('@hermes/ink')"

# ---------- Permissions ----------
# Make install dir world-readable so any HERMES_UID can read it at runtime.
# The venv needs to be traversable too.
USER root
RUN chmod -R a+rX /opt/hermes
# Start as root so the entrypoint can usermod/groupmod + gosu.
# If HERMES_UID is unset, the entrypoint drops to the default hermes user (10000).

# ---------- Python virtualenv ----------
# Trimmed dependency set — excludes homeassistant and rl (toolset definitions
# already removed from the source tree).
# Override pyproject.toml [tool.uv] exclude-newer — the Docker image is a
# self-contained deployment whose packages are locked at build time.
ENV UV_EXCLUDE_NEWER=""
RUN uv venv && \
    uv pip install --no-cache-dir -e ".[modal,daytona,vercel,messaging,cron,cli,tts-premium,slack,pty,honcho,mcp,sms,acp,voice,dingtalk,feishu,google,mistral,bedrock,web]"

# ---------- Runtime ----------
ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_HOME=/opt/data
ENV PATH="/opt/data/.local/bin:${PATH}"
VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/usr/bin/tini", "-g", "--", "/opt/hermes/docker/entrypoint.sh" ]
