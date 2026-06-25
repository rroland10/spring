#!/usr/bin/env bash
# Single-node dev chain with a 6-producer vote schedule (no multinode processes).
#
# Use this for wallet / vote UI testing when 6 physical nodeos instances are
# not needed or the host cannot run them all at once.
#
# Usage:
#   bash scripts/start-6bp-lite.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SIKACHAIN_DEV="${SIKACHAIN_DEV:-1}"
export SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT:-sika}"
export ENABLE_SHIP="${ENABLE_SHIP:-1}"

bash "${SCRIPT_DIR}/stop-bp-cluster.sh" 2>/dev/null || true
bash "${SCRIPT_DIR}/write-lite-producer-config.sh"
bash "${SCRIPT_DIR}/start-node.sh" --daemon
bash "${SCRIPT_DIR}/wait-for-rpc.sh"
BP_CLUSTER_SIZE=6 bash "${SCRIPT_DIR}/vote-bp-schedule.sh"
ENSURE_WAIT=1 bash "${SCRIPT_DIR}/ensure-producer-schedule.sh"

echo ""
echo "6-BP lite mode: single nodeos as sikabpa + 6-producer schedule."
echo "  RPC: http://127.0.0.1:8888"
echo "  Real rotation: bash scripts/start-6bp-cluster.sh"
