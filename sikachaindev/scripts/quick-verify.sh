#!/usr/bin/env bash
# Fast daily verification — read-only chain smoke + feature matrix (no on-chain txs, no Playwright).
#
# Usage:
#   export SIKACHAIN_DEV=1 SIKA_SYSTEM_ACCOUNT=sika
#   bash scripts/quick-verify.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

export SIKACHAIN_DEV="${SIKACHAIN_DEV:-1}"
export SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT:-sika}"

echo "=== quick-verify (read-only) ==="
echo "  RPC=${NODE_URL}"
echo ""

bash "${SCRIPT_DIR}/smoke-phase3.sh"
WALLET_READY=1 bash "${SCRIPT_DIR}/check-hyperion.sh"
WALLET_UI=0 ON_CHAIN=0 bash "${SCRIPT_DIR}/test-features.sh"

if is_multinode_cluster; then
  echo ""
  bash "${SCRIPT_DIR}/ensure-bp-cluster-healthy.sh" || true
  bash "${SCRIPT_DIR}/verify-6bp-rotation.sh"
elif [[ "${VERIFY_MULTINODE:-0}" == "1" ]]; then
  echo ""
  echo "=== verify-6bp-rotation ==="
  echo "SKIP (multinode cluster not running — start with start-6bp-cluster.sh)"
fi

echo ""
echo "=== quick-verify complete — all checks passed ==="
