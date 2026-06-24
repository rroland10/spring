#!/usr/bin/env bash
# Fast Phase 3 smoke — no on-chain transactions (unlike verify-dev).
#
# Usage:
#   export SIKACHAIN_DEV=1 SIKA_SYSTEM_ACCOUNT=sika
#   bash scripts/smoke-phase3.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

export SIKACHAIN_DEV="${SIKACHAIN_DEV:-1}"
export SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT:-sika}"

echo "=== Phase 3 smoke (read-only) ==="
bash "${SCRIPT_DIR}/wait-for-rpc.sh" 360
bash "${SCRIPT_DIR}/check-health.sh"
bash "${SCRIPT_DIR}/verify-phase3.sh"
bash "${SCRIPT_DIR}/smoke-dev-accounts.sh"
bash "${SCRIPT_DIR}/check-hyperion.sh" 2>/dev/null || echo "  --  Hyperion optional (bash scripts/start-hyperion.sh)"
bash "${SCRIPT_DIR}/smoke-wallet.sh" sikadev
echo "=== smoke-phase3 complete ==="
