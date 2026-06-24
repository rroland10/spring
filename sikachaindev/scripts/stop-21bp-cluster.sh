#!/usr/bin/env bash
# Stop 21-node cluster — wrapper around stop-bp-cluster.sh.
set -euo pipefail
export BP_CLUSTER_SIZE=21
exec bash "$(cd "$(dirname "$0")" && pwd)/stop-bp-cluster.sh"
