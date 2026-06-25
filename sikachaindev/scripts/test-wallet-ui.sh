#!/usr/bin/env bash
# Playwright wallet UI tests against live SikaChainDev (WharfKit dev wallet / sikadev).
#
# Prerequisites:
#   bash scripts/launch-ecosystem.sh --quick
#   bash scripts/start-app.sh   # or app already on :3003 with NEXT_PUBLIC_DEV_WALLET=1
#
# Usage:
#   bash scripts/test-wallet-ui.sh
#   PLAYWRIGHT_LIVE=0 bash scripts/test-wallet-ui.sh   # spin up isolated dev server on :3099
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
APP_URL="${SIKA_APP_URL:-http://127.0.0.1:3003}"
REUSE="${PLAYWRIGHT_REUSE_SERVER:-1}"

echo "=== Sika wallet UI tests (WharfKit dev wallet / sikadev) ==="
echo "  RPC=${NODE_URL}  app=${APP_URL}"
echo ""

bash "${SCRIPT_DIR}/wait-for-rpc.sh" 120

if [[ "${REUSE}" == "1" ]]; then
  bash "${SCRIPT_DIR}/ensure-wallet-app.sh"
fi

# Ensure phase3 env includes dev wallet flags
bash "${SCRIPT_DIR}/sync-dev-env.sh" 2>/dev/null || true

# Headless dev-wallet click works after SessionKit init — enable by default.
# Set PLAYWRIGHT_SKIP_DEV_CONNECT=1 to skip the click-to-login test.
PLAYWRIGHT_SKIP_DEV_CONNECT="${PLAYWRIGHT_SKIP_DEV_CONNECT:-0}"
# Live on-chain send (sikadev → sikauser1) — set ON_CHAIN_SEND=1 to enable.
PLAYWRIGHT_SKIP_ON_CHAIN_SEND="${PLAYWRIGHT_SKIP_ON_CHAIN_SEND:-1}"
if [[ "${ON_CHAIN_SEND:-0}" == "1" ]]; then
  PLAYWRIGHT_SKIP_ON_CHAIN_SEND=0
fi

cd "${APP_DIR}"

export PLAYWRIGHT_LIVE_CHAIN=1
export PLAYWRIGHT_SKIP_DEV_CONNECT
export PLAYWRIGHT_SKIP_ON_CHAIN_SEND

if [[ "${REUSE}" == "1" ]]; then
  PLAYWRIGHT_BASE_URL="${APP_URL}" \
  PLAYWRIGHT_REUSE_SERVER=1 \
  npx playwright test e2e/live-chain.spec.ts --project=live-chain-chrome
else
  PLAYWRIGHT_PORT=3099 \
  PLAYWRIGHT_ISOLATED=1 \
  npx playwright test e2e/live-chain.spec.ts --project=live-chain-chrome
fi

echo ""
echo "=== wallet UI tests complete ==="
