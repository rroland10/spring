#!/usr/bin/env bash
# Live-chain Playwright: business MSIG propose → approve → exec (sikadev → sikauser1).
#
# Prerequisites:
#   bash scripts/launch-ecosystem.sh --quick
#   bash scripts/deploy-msig.sh          # sika.msig privileged
#   bash scripts/start-app.sh            # NEXT_PUBLIC_DEV_WALLET=1 on :3003
#
# Usage:
#   bash scripts/test-wallet-msig.sh
#   PLAYWRIGHT_REUSE_SERVER=1 bash scripts/test-wallet-msig.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
APP_URL="${SIKA_APP_URL:-http://127.0.0.1:3003}"
REUSE="${PLAYWRIGHT_REUSE_SERVER:-1}"

echo "=== Sika wallet MSIG live tests (sikadev) ==="
echo "  RPC=${NODE_URL}  app=${APP_URL}"
echo ""

bash "${SCRIPT_DIR}/wait-for-rpc.sh" 120

MSIG="${MSIG_ACCOUNT:-sika.msig}"
if ! curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${MSIG}\"}" >/dev/null 2>&1; then
  echo "error: ${MSIG} not deployed — run: bash scripts/deploy-msig.sh" >&2
  exit 1
fi

bash "${SCRIPT_DIR}/sync-dev-env.sh" 2>/dev/null || true

if [[ "${MSIG_CLEANUP:-1}" == "1" ]]; then
  bash "${SCRIPT_DIR}/cleanup-msig-proposals.sh" || true
fi

if [[ "${REUSE}" == "1" ]]; then
  bash "${SCRIPT_DIR}/ensure-wallet-app.sh"
fi

cd "${APP_DIR}"

export PLAYWRIGHT_LIVE_CHAIN=1
export PLAYWRIGHT_SKIP_DEV_CONNECT=1
export PLAYWRIGHT_SKIP_ON_CHAIN_SEND=0

if [[ "${REUSE}" == "1" ]]; then
  PLAYWRIGHT_BASE_URL="${APP_URL}" \
  PLAYWRIGHT_REUSE_SERVER=1 \
  npx playwright test e2e/live-chain-msig.spec.ts --project=live-chain-chrome
else
  PLAYWRIGHT_PORT=3099 \
  PLAYWRIGHT_ISOLATED=1 \
  npx playwright test e2e/live-chain-msig.spec.ts --project=live-chain-chrome
fi

echo ""
echo "=== wallet MSIG tests complete ==="
