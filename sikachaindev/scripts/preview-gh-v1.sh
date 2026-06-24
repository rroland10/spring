#!/usr/bin/env bash
# Local Ghana v1 wallet preview — gh-v1 rollout surface against SikaChainDev.
#
# Usage:
#   bash scripts/preview-gh-v1.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
GH_V1_ENV="${APP_DIR}/.env.sikachaindev.gh-v1"

bash "${SCRIPT_DIR}/sync-dev-env.sh" 2>/dev/null || node "${SCRIPT_DIR}/sync-app-env.mjs"

if [[ ! -f "${GH_V1_ENV}" ]]; then
  echo "error: missing ${GH_V1_ENV}" >&2
  exit 1
fi

cp "${GH_V1_ENV}" "${APP_DIR}/.env.local"
echo "=== Ghana v1 preview ==="
echo "  env:  ${APP_DIR}/.env.local  (from .env.sikachaindev.gh-v1)"
echo "  RPC:  http://127.0.0.1:8888  (start chain if needed: bash scripts/start-all.sh)"
echo ""
echo "Start wallet:"
echo "  cd \"${APP_DIR}\" && npm run dev"
echo ""
echo "Verify rollout gating:"
echo "  bash scripts/verify-gh-v1.sh"
