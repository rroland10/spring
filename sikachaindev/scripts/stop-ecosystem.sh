#!/usr/bin/env bash
# Stop SikaChainDev ecosystem apps + chain (keeps Hyperion Docker deps running).
#
# Usage:
#   bash scripts/stop-ecosystem.sh           # chain + Node apps
#   bash scripts/stop-ecosystem.sh --hyperion  # also stop Hyperion API/indexer containers
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

stop_port() {
  local port="$1"
  local label="$2"
  local pids
  pids="$(lsof -tiTCP:"${port}" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "${pids}" ]]; then
    echo "Stopping ${label} (:${port})..."
    echo "${pids}" | xargs kill -TERM 2>/dev/null || true
    sleep 1
    echo "${pids}" | xargs kill -KILL 2>/dev/null || true
  fi
}

echo "=== Stop SikaChainDev ecosystem ==="

DATA_DIR="${ROOT}/data"
PID_FILE="${DATA_DIR}/ecosystem.pid"
if [[ -f "${PID_FILE}" ]]; then
  LAUNCHER_PID="$(cat "${PID_FILE}")"
  if kill -0 "${LAUNCHER_PID}" 2>/dev/null; then
    echo "Stopping ecosystem launcher (pid ${LAUNCHER_PID})..."
    kill -TERM "${LAUNCHER_PID}" 2>/dev/null || true
    sleep 1
  fi
  rm -f "${PID_FILE}"
fi

stop_port "${SIKA_APP_PORT}" "Sika app"
stop_port "${SIKA_CHAIN_WEB_PORT}" "SikaChain site"
stop_port 4000 "Wharfkit adapter"

bash "${SCRIPT_DIR}/stop-all.sh"

if [[ "${1:-}" == "--hyperion" ]]; then
  bash "${SCRIPT_DIR}/stop-hyperion.sh" 2>/dev/null || true
  echo "Hyperion containers stopped"
fi

echo "Done."
