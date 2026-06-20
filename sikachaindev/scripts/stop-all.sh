#!/usr/bin/env bash
# Stop keosd + nodeos for SikaChainDev.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${ROOT}/data"

bash "${SCRIPT_DIR}/stop-node.sh"

if [[ -f "${DATA_DIR}/keosd.pid" ]]; then
  PID="$(cat "${DATA_DIR}/keosd.pid")"
  if kill -0 "${PID}" 2>/dev/null; then
    kill -TERM "${PID}" 2>/dev/null || true
    for _ in $(seq 1 10); do
      kill -0 "${PID}" 2>/dev/null || break
      sleep 0.3
    done
  fi
  rm -f "${DATA_DIR}/keosd.pid"
fi

lsof -ti :8899 | xargs kill -TERM 2>/dev/null || true
pkill -f "keosd.*${ROOT}/wallet" 2>/dev/null || true

echo "keosd stopped"
