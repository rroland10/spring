#!/usr/bin/env bash
# Wait until nodeos RPC responds (handles replay after unclean shutdown).
#
# Usage:
#   bash scripts/wait-for-rpc.sh              # default 360s (large replay after unclean shutdown)
#   bash scripts/wait-for-rpc.sh 300          # custom timeout
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

TIMEOUT="${1:-360}"
DATA_DIR="${ROOT}/data"
LOG="${DATA_DIR}/nodeos.log"

echo "Waiting for RPC at ${NODE_URL} (up to ${TIMEOUT}s; replay of 60k+ blocks may take 3–4 min)..."

for i in $(seq 1 "${TIMEOUT}"); do
  if curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null 2>&1; then
    if [[ "${i}" -gt 3 ]]; then
      echo "  RPC ready (${i}s)"
    fi
    exit 0
  fi
  if (( i % 15 == 0 )); then
    echo "  still waiting (${i}s) — tail -f ${LOG}"
  fi
  sleep 1
done

echo "error: RPC not ready after ${TIMEOUT}s — check ${LOG}" >&2
exit 1
