#!/usr/bin/env bash
# Register and vote 6 block producers (sikabpa–sikabpf) on a running chain.
# Lighter than bootstrap-21bp.sh — enough for 6-BP dev / multinode testing.
#
# Usage:
#   bash scripts/bootstrap-6bp.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PRODUCERS_JSON="${PRODUCERS_JSON:-${SCRIPT_DIR}/../config/producers-6.json}"
export BP_CLUSTER_SIZE=6

# Reuse 21-BP bootstrap (create/stake/register) but limit to producers-6.json.
bash "${SCRIPT_DIR}/bootstrap-21bp.sh"

echo ""
echo "Activating producer schedule (requires upgraded sika.system)..."
BP_CLUSTER_SIZE=6 ENSURE_WAIT=1 bash "${SCRIPT_DIR}/ensure-producer-schedule.sh"
