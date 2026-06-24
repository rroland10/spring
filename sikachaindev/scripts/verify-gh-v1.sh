#!/usr/bin/env bash
# Ghana v1 rollout verification — env template + Playwright gating tests.
#
# Usage:
#   bash scripts/verify-gh-v1.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
GH_V1_ENV="${APP_DIR}/.env.sikachaindev.gh-v1"

echo "=== verify-gh-v1 ==="

bash "${SCRIPT_DIR}/sync-dev-env.sh" 2>/dev/null || true

if [[ ! -f "${GH_V1_ENV}" ]]; then
  echo "FAIL: missing ${GH_V1_ENV} — run sync-dev-env.sh" >&2
  exit 1
fi

if ! grep -q '^NEXT_PUBLIC_WALLET_ROLLOUT=gh-v1' "${GH_V1_ENV}"; then
  echo "FAIL: ${GH_V1_ENV} missing NEXT_PUBLIC_WALLET_ROLLOUT=gh-v1" >&2
  exit 1
fi
echo "  env template .env.sikachaindev.gh-v1          ok"

bash "${SCRIPT_DIR}/test-wallet-gh-v1.sh"
echo "  test-wallet-gh-v1.sh                          ok"

echo ""
echo "=== verify-gh-v1 complete ==="
