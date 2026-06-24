#!/usr/bin/env bash
# Post-deploy gate for a **hosted** SikaChain testnet (not local SikaChainDev).
#
# Usage:
#   NODE_URL=https://rpc.testnet.sikachain.gh \
#   EXPECT_CHAIN_ID=<chain-id> \
#   HYPERION_URL=https://hyperion.testnet.sikachain.gh \
#   bash scripts/verify-predeploy-remote.sh
#
# Optional:
#   VERIFY_WALLET_URL=https://app.sikachain.gh  # curl smoke
#   VERIFY_SITE_URL=https://sikachain.com
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

: "${NODE_URL:?set NODE_URL to public HTTPS RPC}"
: "${EXPECT_CHAIN_ID:?set EXPECT_CHAIN_ID}"

echo "=== verify-predeploy-remote (hosted testnet) ==="
echo "  NODE_URL=${NODE_URL}"
echo "  EXPECT_CHAIN_ID=${EXPECT_CHAIN_ID}"
echo "  HYPERION_URL=${HYPERION_URL:-<unset>}"
echo ""

echo "--- Offline templates ---"
bash "${SCRIPT_DIR}/check-launch-ready.sh"

echo ""
bash "${SCRIPT_DIR}/verify-testnet.sh"

if [[ -n "${VERIFY_WALLET_URL:-}" ]]; then
  echo ""
  echo "--- Wallet app ---"
  if curl -sf "${VERIFY_WALLET_URL}/app/home" >/dev/null; then
    echo "  ok  ${VERIFY_WALLET_URL}/app/home"
  else
    echo "  FAIL ${VERIFY_WALLET_URL}/app/home" >&2
    exit 1
  fi
fi

if [[ -n "${VERIFY_SITE_URL:-}" ]]; then
  echo ""
  echo "--- GTM site ---"
  if curl -sf "${VERIFY_SITE_URL}" >/dev/null; then
    echo "  ok  ${VERIFY_SITE_URL}"
  else
    echo "  FAIL ${VERIFY_SITE_URL}" >&2
    exit 1
  fi
fi

echo ""
echo "=== verify-predeploy-remote complete ==="
echo "  Run gh-v1 wallet smoke against production app with Anchor on testnet chain ID"
echo "  See docs/gh-v1-launch.md section 5"
