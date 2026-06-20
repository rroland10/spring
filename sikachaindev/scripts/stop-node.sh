#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${ROOT}/data"
PID_FILE="${DATA_DIR}/nodeos.pid"

graceful=0
if [[ -f "${PID_FILE}" ]]; then
  PID="$(cat "${PID_FILE}")"
  if kill -0 "${PID}" 2>/dev/null; then
    graceful=1
    kill -TERM "${PID}"
    for _ in $(seq 1 20); do
      kill -0 "${PID}" 2>/dev/null || break
      sleep 0.5
    done
  fi
  rm -f "${PID_FILE}"
fi
if pkill -f "nodeos.*${DATA_DIR}" 2>/dev/null; then
  graceful=1
  sleep 1
fi
if [[ "${graceful}" -eq 1 ]]; then
  touch "${DATA_DIR}/.clean_shutdown" 2>/dev/null || true
else
  rm -f "${DATA_DIR}/.clean_shutdown" 2>/dev/null || true
fi
echo "nodeos stopped"
