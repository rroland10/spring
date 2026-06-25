#!/usr/bin/env bash
# Start 2 producer nodes (sikabpa–sikabpb) — lighter multinode rotation test.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export BP_CLUSTER_SIZE=2
export PRODUCERS_JSON="${SCRIPT_DIR}/../config/producers-2.json"
exec bash "${SCRIPT_DIR}/start-bp-cluster.sh"
