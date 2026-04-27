#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

DEPLOY_ENV_FILE="${DEPLOY_ENV_FILE:-$ROOT_DIR/.deploy.env}"
if [[ -f "$DEPLOY_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DEPLOY_ENV_FILE"
fi

APP_NAME="${APP_NAME:-hermes-agent}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"
INSTALL_EXTRAS="${INSTALL_EXTRAS:-all}"
USE_UV_LOCK="${USE_UV_LOCK:-1}"
RUN_SUBMODULES="${RUN_SUBMODULES:-1}"
BUILD_WEB="${BUILD_WEB:-0}"
WEB_DIR="${WEB_DIR:-web}"
START_HINT="${START_HINT:-hermes gateway run}"

log() {
  printf '[deploy] %s\n' "$*"
}

fail() {
  printf '[deploy] ERROR: %s\n' "$*" >&2
  exit 1
}

ensure_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || fail "missing required command: $cmd"
}

setup_venv() {
  log "preparing virtual environment"

  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    if command -v uv >/dev/null 2>&1; then
      uv venv "$VENV_DIR"
    else
      ensure_cmd "$PYTHON_BIN"
      "$PYTHON_BIN" -m venv "$VENV_DIR"
    fi
  fi

  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"
}

install_python_deps() {
  log "installing python dependencies"

  if command -v uv >/dev/null 2>&1 && [[ "$USE_UV_LOCK" == "1" ]] && [[ -f uv.lock ]]; then
    local -a uv_args
    uv_args=(sync --locked)

    if [[ -n "$INSTALL_EXTRAS" ]]; then
      local extra
      local -a extra_list
      IFS=',' read -r -a extra_list <<< "$INSTALL_EXTRAS"
      for extra in "${extra_list[@]}"; do
        extra="${extra// /}"
        [[ -n "$extra" ]] && uv_args+=(--extra "$extra")
      done
    fi

    UV_PROJECT_ENVIRONMENT="$ROOT_DIR/$VENV_DIR" uv "${uv_args[@]}"
    return
  fi

  python -m pip install --upgrade pip setuptools wheel

  if [[ -n "$INSTALL_EXTRAS" ]]; then
    python -m pip install -e ".[${INSTALL_EXTRAS}]"
  else
    python -m pip install -e "."
  fi
}

update_submodules() {
  if [[ "$RUN_SUBMODULES" != "1" ]] || [[ ! -f .gitmodules ]]; then
    return
  fi

  log "updating submodules"
  git submodule update --init --recursive
}

build_web_assets() {
  if [[ "$BUILD_WEB" != "1" ]]; then
    return
  fi

  [[ -d "$WEB_DIR" ]] || fail "web directory not found: $WEB_DIR"
  ensure_cmd npm

  log "building web assets"
  (
    cd "$WEB_DIR"
    npm install --no-audit
    npm run build
  )
}

print_next_steps() {
  cat <<EOF
[deploy] environment setup complete
[deploy] virtualenv: $ROOT_DIR/$VENV_DIR
[deploy] next step:
  cd "$ROOT_DIR"
  source "$VENV_DIR/bin/activate"
  $START_HINT
EOF
}

main() {
  ensure_cmd git
  ensure_cmd bash

  update_submodules
  setup_venv
  install_python_deps
  build_web_assets
  print_next_steps
}

main "$@"
