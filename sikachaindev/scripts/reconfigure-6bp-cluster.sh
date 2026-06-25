#!/usr/bin/env bash
# Fast multinode restart: rewrite configs (CORS/SHIP/P2P) and restart without re-cloning chain data.
#
# Usage:
#   bash scripts/reconfigure-6bp-cluster.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export BP_CLUSTER_SIZE=6
export BP_RECONFIG_ONLY=1
export BP_SKIP_VOTE=1
export ENABLE_SHIP=1

bash "${SCRIPT_DIR}/stop-bp-cluster.sh"
exec bash "${SCRIPT_DIR}/start-6bp-cluster.sh"
