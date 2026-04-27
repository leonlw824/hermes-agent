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
REMOTE_NAME="${REMOTE_NAME:-origin}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"
INSTALL_EXTRAS="${INSTALL_EXTRAS:-all}"
USE_UV_LOCK="${USE_UV_LOCK:-1}"
RUN_SUBMODULES="${RUN_SUBMODULES:-1}"
BUILD_WEB="${BUILD_WEB:-0}"
WEB_DIR="${WEB_DIR:-web}"
START_CMD="${START_CMD:-hermes gateway run}"
STARTUP_WAIT_SECONDS="${STARTUP_WAIT_SECONDS:-5}"
DEPLOY_STATE_DIR="${DEPLOY_STATE_DIR:-$HOME/.${APP_NAME}/deploy}"
LOG_DIR="${LOG_DIR:-$DEPLOY_STATE_DIR/logs}"
RUN_DIR="${RUN_DIR:-$DEPLOY_STATE_DIR/run}"
PID_FILE="${PID_FILE:-$RUN_DIR/$APP_NAME.pid}"

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

ensure_clean_worktree() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    fail "git worktree has local changes; commit/stash them before deploy"
  fi
}

update_code() {
  log "updating code from $REMOTE_NAME/$DEPLOY_BRANCH"
  ensure_clean_worktree

  git fetch "$REMOTE_NAME" "$DEPLOY_BRANCH"

  if git show-ref --verify --quiet "refs/heads/$DEPLOY_BRANCH"; then
    git checkout "$DEPLOY_BRANCH"
  else
    git checkout -B "$DEPLOY_BRANCH" "$REMOTE_NAME/$DEPLOY_BRANCH"
  fi

  git pull --ff-only "$REMOTE_NAME" "$DEPLOY_BRANCH"

  if [[ "$RUN_SUBMODULES" == "1" ]] && [[ -f .gitmodules ]]; then
    log "updating submodules"
    git submodule update --init --recursive
  fi
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

stop_existing_process() {
  if [[ ! -f "$PID_FILE" ]]; then
    return
  fi

  local old_pid
  old_pid="$(cat "$PID_FILE")"

  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" >/dev/null 2>&1; then
    log "stopping existing process: $old_pid"
    kill "$old_pid" >/dev/null 2>&1 || true

    for _ in $(seq 1 20); do
      if ! kill -0 "$old_pid" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done

    if kill -0 "$old_pid" >/dev/null 2>&1; then
      log "process did not stop gracefully, killing: $old_pid"
      kill -9 "$old_pid" >/dev/null 2>&1 || true
    fi
  fi

  rm -f "$PID_FILE"
}

start_process() {
  mkdir -p "$LOG_DIR" "$RUN_DIR"

  local log_file
  log_file="$LOG_DIR/${APP_NAME}-$(date +%Y%m%d-%H%M%S).log"

  log "starting process: $START_CMD"
  nohup bash -lc "cd \"$ROOT_DIR\" && source \"$ROOT_DIR/$VENV_DIR/bin/activate\" && exec $START_CMD" \
    >"$log_file" 2>&1 &

  local new_pid=$!
  echo "$new_pid" >"$PID_FILE"

  sleep "$STARTUP_WAIT_SECONDS"

  if ! kill -0 "$new_pid" >/dev/null 2>&1; then
    tail -n 100 "$log_file" >&2 || true
    fail "process exited during startup; check log: $log_file"
  fi

  log "deploy complete"
  log "pid: $new_pid"
  log "log: $log_file"
  log "commit: $(git rev-parse --short HEAD)"
}

main() {
  ensure_cmd git
  ensure_cmd bash

  update_code
  setup_venv
  install_python_deps
  build_web_assets
  stop_existing_process
  start_process
}

main "$@"
