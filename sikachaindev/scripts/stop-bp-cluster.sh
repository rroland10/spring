#!/usr/bin/env bash
# Stop multinode BP cluster (default: up to 6 nodes; set BP_CLUSTER_SIZE=21 for full set).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MULTINODE="${ROOT}/data/multinode"
NUM="${BP_CLUSTER_SIZE:-6}"

stopped=0
for idx in $(seq 1 "${NUM}"); do
  pid_file="${MULTINODE}/node${idx}/nodeos.pid"
  if [[ -f "${pid_file}" ]]; then
    pid="$(cat "${pid_file}")"
    if kill -0 "${pid}" 2>/dev/null; then
      kill -TERM "${pid}" 2>/dev/null || true
      stopped=$((stopped + 1))
      for _ in $(seq 1 20); do
        kill -0 "${pid}" 2>/dev/null || break
        sleep 0.5
      done
    fi
    rm -f "${pid_file}"
  fi
done

if pkill -f "nodeos.*${MULTINODE}/node" 2>/dev/null; then
  stopped=$((stopped + 1))
  sleep 1
fi

echo "Stopped ${stopped} multinode producer(s)."
echo "Restart single-node dev chain: ENABLE_SHIP=1 bash scripts/start-node.sh --daemon"
