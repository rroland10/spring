#!/usr/bin/env bash
# Full SikaChainDev stack verification — build gate, on-chain txs, apps, Playwright.
#
# Usage:
#   export SIKACHAIN_DEV=1 SIKA_SYSTEM_ACCOUNT=sika
#   bash scripts/verify-stack.sh                    # verify-all + feature matrix + UI
#   VERIFY_UI=0 bash scripts/verify-stack.sh        # skip Playwright (faster)
#   VERIFY_DEV=0 bash scripts/verify-stack.sh        # skip on-chain verify-dev txs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

export SIKACHAIN_DEV="${SIKACHAIN_DEV:-1}"
export SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT:-sika}"

VERIFY_UI="${VERIFY_UI:-1}"
VERIFY_DEV="${VERIFY_DEV:-1}"
VERIFY_WEB="${VERIFY_WEB:-0}"

echo "=== verify-stack ==="
echo "  RPC=${NODE_URL}  VERIFY_DEV=${VERIFY_DEV}  VERIFY_UI=${VERIFY_UI}  VERIFY_WEB=${VERIFY_WEB}"
echo ""

if [[ "${VERIFY_UI}" == "1" ]]; then
  echo "=== wallet-ready (RPC + Hyperion) ==="
  bash "${SCRIPT_DIR}/wallet-ready.sh"
  echo ""
fi

if [[ "${VERIFY_DEV}" == "1" ]]; then
  VERIFY_DEV=1 bash "${SCRIPT_DIR}/verify-all.sh"
else
  bash "${SCRIPT_DIR}/verify-all.sh"
fi

echo ""
echo "=== Feature matrix ==="
# verify-all already runs verify-dev when VERIFY_DEV=1 — avoid duplicate on-chain gate here.
FEATURE_ON_CHAIN=0
if [[ "${VERIFY_UI}" == "1" ]]; then
  VERIFY_DEV_ON_CHAIN_SEND="${VERIFY_DEV}" ON_CHAIN="${FEATURE_ON_CHAIN}" WALLET_UI=1 PLAYWRIGHT_REUSE_SERVER=1 \
    bash "${SCRIPT_DIR}/test-features.sh"
else
  ON_CHAIN="${FEATURE_ON_CHAIN}" bash "${SCRIPT_DIR}/test-features.sh"
fi

if [[ "${VERIFY_WEB}" == "1" ]]; then
  WEB_DIR="${SIKA_CHAIN_WEB_DIR:-/Users/randallroland/Desktop/Projects/SikaChain}"
  if [[ -f "${WEB_DIR}/package.json" ]]; then
    echo ""
    echo "=== SikaChain marketing site ==="
    (cd "${WEB_DIR}" && npm run verify:stack)
  else
    echo ""
    echo "=== SikaChain marketing site ==="
    echo "  SKIP (SIKA_CHAIN_WEB_DIR not found)"
  fi
fi

if is_multinode_cluster; then
  echo ""
  bash "${SCRIPT_DIR}/ensure-bp-cluster-healthy.sh" || true
  bash "${SCRIPT_DIR}/verify-6bp-rotation.sh"
elif [[ "${VERIFY_MULTINODE:-0}" == "1" ]]; then
  echo ""
  echo "=== verify-6bp-rotation ==="
  echo "  SKIP (multinode cluster not running)"
fi

if [[ "${LAUNCH_READY:-0}" == "1" ]]; then
  echo ""
  bash "${SCRIPT_DIR}/check-launch-ready.sh"
fi

echo ""
echo "=== verify-stack complete — all checks passed ==="
