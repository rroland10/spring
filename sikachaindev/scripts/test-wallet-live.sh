#!/usr/bin/env bash
# Playwright live-chain wallet gate: UI smoke + business MSIG (sikadev) + import from chain.
#
# Prerequisites:
#   bash scripts/launch-ecosystem.sh --quick
#   bash scripts/start-app.sh
#   bash scripts/deploy-msig.sh
#
# Usage:
#   bash scripts/test-wallet-live.sh
#   ON_CHAIN_SEND=0 bash scripts/test-wallet-live.sh   # skip CGHS transfer (faster)
#   GH_V1=1 bash scripts/test-wallet-live.sh           # also run gh-v1 rollout spec (22 tests total)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

export PLAYWRIGHT_REUSE_SERVER="${PLAYWRIGHT_REUSE_SERVER:-1}"
export ON_CHAIN_SEND="${ON_CHAIN_SEND:-1}"
export PLAYWRIGHT_SKIP_DEV_CONNECT="${PLAYWRIGHT_SKIP_DEV_CONNECT:-0}"
export GH_V1="${GH_V1:-0}"

echo "=== Sika wallet live Playwright gate ==="
echo "  RPC=${NODE_URL}  app=${SIKA_APP_URL:-http://127.0.0.1:3003}"
echo "  REUSE=${PLAYWRIGHT_REUSE_SERVER}  ON_CHAIN_SEND=${ON_CHAIN_SEND}  GH_V1=${GH_V1}"
echo ""

ON_CHAIN_SEND="${ON_CHAIN_SEND}" bash "${SCRIPT_DIR}/test-wallet-ui.sh"
bash "${SCRIPT_DIR}/test-wallet-msig.sh"

if [[ "${BIZ_MSIG_IMPORT:-1}" == "1" ]]; then
  bash "${SCRIPT_DIR}/setup-biz-msig-dev.sh"
  APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
  (
    cd "${APP_DIR}"
    PLAYWRIGHT_LIVE_CHAIN=1 \
    PLAYWRIGHT_SKIP_DEV_CONNECT=1 \
    PLAYWRIGHT_SKIP_ON_CHAIN_SEND=1 \
    PLAYWRIGHT_BASE_URL="${SIKA_APP_URL:-http://127.0.0.1:3003}" \
    PLAYWRIGHT_REUSE_SERVER=1 \
    npx playwright test e2e/live-chain-business.spec.ts --project=live-chain-chrome
  )
  echo "  live-chain-business.spec.ts                   ok"
fi

if [[ "${GH_V1}" == "1" ]]; then
  bash "${SCRIPT_DIR}/test-wallet-gh-v1.sh"
fi

echo ""
echo "=== wallet live tests complete ==="
