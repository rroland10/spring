#!/usr/bin/env bash
# Restart SikaChainDev nodeos with SHIP (state_history) for Hyperion indexing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export ENABLE_SHIP=1

echo "=== Restart nodeos with SHIP (ws://127.0.0.1:8080) ==="
bash "${SCRIPT_DIR}/stop-all.sh"
bash "${SCRIPT_DIR}/start-all.sh"

echo "Waiting for RPC + SHIP..."
for _ in $(seq 1 120); do
  curl -sf "http://127.0.0.1:8888/v1/chain/get_info" >/dev/null 2>&1 || { sleep 2; continue; }
  if bash "${SCRIPT_DIR}/check-ship.sh" 2>/dev/null; then
    echo "SHIP ready for Hyperion"
    break
  fi
  sleep 2
done

if ! bash "${SCRIPT_DIR}/check-ship.sh" 2>/dev/null; then
  echo "note: SHIP not up — check data/nodeos.log (replay may still be running)"
  tail -8 "${SCRIPT_DIR}/../data/nodeos.log" 2>/dev/null || true
fi

bash "${SCRIPT_DIR}/setup-wallet.sh" 2>/dev/null || true
bash "${SCRIPT_DIR}/check-health.sh" 2>/dev/null || true
