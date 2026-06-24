#!/usr/bin/env bash
# Pre-deploy gate — templates, live chain, full stack URLs, optional gh-v1 Playwright.
#
# Usage:
#   bash scripts/verify-predeploy.sh              # launch-ready + GTM stack health
#   GH_V1=1 bash scripts/verify-predeploy.sh      # + verify-gh-v1 Playwright
#   FULL=1 bash scripts/verify-predeploy.sh       # + GH_V1=1 test-wallet-live (slow)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

WEB_DIR="${SIKA_CHAIN_WEB_DIR:-/Users/randallroland/Desktop/Projects/SikaChain}"
GH_V1="${GH_V1:-0}"
FULL="${FULL:-0}"

echo "=== verify-predeploy (sika + gh-v1 + stack URLs) ==="
echo "  GH_V1=${GH_V1}  FULL=${FULL}"
echo ""

bash "${SCRIPT_DIR}/check-launch-ready.sh"

echo ""
echo "=== SikaChain marketing + wallet URLs ==="
if [[ -f "${WEB_DIR}/package.json" ]]; then
  (cd "${WEB_DIR}" && npm run verify:stack)
else
  echo "  SKIP (SIKA_CHAIN_WEB_DIR not found: ${WEB_DIR})"
fi

if [[ "${GH_V1}" == "1" || "${FULL}" == "1" ]]; then
  echo ""
  bash "${SCRIPT_DIR}/verify-gh-v1.sh"
fi

if [[ "${FULL}" == "1" ]]; then
  echo ""
  GH_V1=1 PLAYWRIGHT_REUSE_SERVER=1 bash "${SCRIPT_DIR}/test-wallet-live.sh"
fi

echo ""
echo "=== verify-predeploy complete — ready for testnet deploy prep ==="
echo "  Wallet env:  Sika app/.env.production.gh-v1.example"
echo "  Anchor:      sikachaindev/anchor-chain.testnet.example.json"
echo "  Checklist:   docs/gh-v1-launch.md"
echo "  Testnet:     docs/testnet-deploy.md"
