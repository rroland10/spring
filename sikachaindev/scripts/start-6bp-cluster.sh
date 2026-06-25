#!/usr/bin/env bash
# Start 6 producer nodes (sikabpa–sikabpf) for rotation testing.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export BP_CLUSTER_SIZE=6
export PRODUCERS_JSON="${SCRIPT_DIR}/../config/producers-6.json"
exec bash "${SCRIPT_DIR}/start-bp-cluster.sh"
