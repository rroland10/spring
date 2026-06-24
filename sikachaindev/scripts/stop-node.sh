#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${ROOT}/data"
PID_FILE="${DATA_DIR}/nodeos.pid"

# Only stop the single-node instance (--data-dir exactly ${DATA_DIR}), not multinode cluster nodes.
single_node_pids() {
  pgrep -fl nodeos 2>/dev/null | grep -F -- "--data-dir ${DATA_DIR} --genesis" | awk '{print $1}' || true
}

graceful=0
used_kill=0
if [[ -f "${PID_FILE}" ]]; then
  PID="$(cat "${PID_FILE}")"
  if kill -0 "${PID}" 2>/dev/null; then
    graceful=1
    kill -TERM "${PID}"
    for _ in $(seq 1 20); do
      kill -0 "${PID}" 2>/dev/null || break
      sleep 0.5
    done
    if kill -0 "${PID}" 2>/dev/null; then
      used_kill=1
    fi
  fi
  rm -f "${PID_FILE}"
fi
while read -r pid; do
  [[ -n "${pid}" ]] || continue
  kill -TERM "${pid}" 2>/dev/null || true
  graceful=1
done < <(single_node_pids)
for _ in $(seq 1 10); do
  [[ -z "$(single_node_pids)" ]] && break
  sleep 0.5
done
while read -r pid; do
  [[ -n "${pid}" ]] || continue
  kill -KILL "${pid}" 2>/dev/null || true
  used_kill=1
done < <(single_node_pids)
sleep 1
if [[ "${graceful}" -eq 1 && "${used_kill}" -eq 0 ]]; then
  touch "${DATA_DIR}/.clean_shutdown" 2>/dev/null || true
else
  rm -f "${DATA_DIR}/.clean_shutdown" 2>/dev/null || true
fi
echo "nodeos stopped"
