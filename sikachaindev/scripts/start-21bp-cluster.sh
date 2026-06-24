#!/usr/bin/env bash
# Start 21 producer nodes — wrapper around start-bp-cluster.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export BP_CLUSTER_SIZE=21
export PRODUCERS_JSON="${SCRIPT_DIR}/../config/producers-21.json"
exec bash "${SCRIPT_DIR}/start-bp-cluster.sh"
