#!/usr/bin/env bash
# One-shot SikaChainDev prep: chain bootstrap, bindings, app env sync.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
ADAPTER_DIR="${SIKA_ADAPTER_DIR:-/Users/randallroland/Desktop/Projects/wharfkit adapter}"

bash "${SCRIPT_DIR}/bootstrap-dev.sh"

if curl -sf "${NODE_URL:-http://127.0.0.1:8888}/v1/chain/get_info" >/dev/null 2>&1; then
  bash "${SCRIPT_DIR}/generate-bindings.sh"
else
  echo "warning: nodeos not reachable — skipped generate-bindings.sh"
fi

if [[ -f "${APP_DIR}/.env.sikachaindev" ]]; then
  cp "${APP_DIR}/.env.sikachaindev" "${APP_DIR}/.env.local"
  echo "Synced ${APP_DIR}/.env.local"
fi

if [[ -f "${ADAPTER_DIR}/.env.example" ]] && [[ ! -f "${ADAPTER_DIR}/.env" ]]; then
  cp "${ADAPTER_DIR}/.env.example" "${ADAPTER_DIR}/.env"
  echo "Created ${ADAPTER_DIR}/.env"
fi

echo ""
bash "${SCRIPT_DIR}/ecosystem-status.sh"

echo ""
echo "=== Run app ==="
if curl -sf -o /dev/null -w "" http://127.0.0.1:3000/ 2>/dev/null; then
  echo "  App already running at http://127.0.0.1:3000"
else
  echo "  cd \"${APP_DIR}\" && npm run dev"
fi
