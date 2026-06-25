#!/usr/bin/env bash
# Playwright: Ghana v1 rollout surface (hides swap, pro tools from hubs).
#
# Spins an isolated app on :3099 with NEXT_PUBLIC_WALLET_ROLLOUT=gh-v1.
#
# Usage:
#   bash scripts/test-wallet-gh-v1.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"

echo "=== Sika wallet Ghana v1 rollout tests ==="
echo "  isolated app :3099  NEXT_PUBLIC_WALLET_ROLLOUT=gh-v1"
echo ""

bash "${SCRIPT_DIR}/sync-dev-env.sh" 2>/dev/null || true

cd "${APP_DIR}"

# Live-chain gate sets REUSE=1 for :3003 — gh-v1 needs an isolated dev server on :3099.
unset PLAYWRIGHT_REUSE_SERVER PLAYWRIGHT_BASE_URL PLAYWRIGHT_LIVE_CHAIN
export PLAYWRIGHT_GH_V1=1
export NEXT_PUBLIC_WALLET_ROLLOUT=gh-v1
export PLAYWRIGHT_PORT=3099
export PLAYWRIGHT_ISOLATED=1

npx playwright test e2e/wallet-rollout.spec.ts --project=gh-v1-chrome

echo ""
echo "=== wallet gh-v1 tests complete ==="
