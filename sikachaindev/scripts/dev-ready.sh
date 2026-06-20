#!/usr/bin/env bash
# One-shot SikaChainDev prep: chain bootstrap, bindings, app env sync.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"
APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
WEB_DIR="${SIKA_CHAIN_WEB_DIR:-/Users/randallroland/Desktop/Projects/SikaChain}"
ADAPTER_DIR="${SIKA_ADAPTER_DIR:-/Users/randallroland/Desktop/Projects/wharfkit adapter}"

bash "${SCRIPT_DIR}/bootstrap-dev.sh"

if curl -sf "${NODE_URL:-http://127.0.0.1:8888}/v1/chain/get_info" >/dev/null 2>&1; then
  bash "${SCRIPT_DIR}/generate-bindings.sh"
else
  echo "warning: nodeos not reachable — skipped generate-bindings.sh"
fi

if [[ -f "${APP_DIR}/.env.sikachaindev" ]]; then
  if [[ "${SIKACHAIN_DEV:-}" == "1" ]] && [[ -f "${APP_DIR}/.env.sikachaindev.phase3" ]]; then
    cp "${APP_DIR}/.env.sikachaindev.phase3" "${APP_DIR}/.env.local"
    echo "Synced ${APP_DIR}/.env.local (Phase 3 — system account sika)"
  else
    cp "${APP_DIR}/.env.sikachaindev" "${APP_DIR}/.env.local"
    echo "Synced ${APP_DIR}/.env.local"
  fi
fi

if [[ -f "${ADAPTER_DIR}/.env.example" ]] && [[ ! -f "${ADAPTER_DIR}/.env" ]]; then
  cp "${ADAPTER_DIR}/.env.example" "${ADAPTER_DIR}/.env"
  echo "Created ${ADAPTER_DIR}/.env"
fi

if [[ -f "${WEB_DIR}/.env.example" ]] && [[ ! -f "${WEB_DIR}/.env" ]]; then
  cp "${WEB_DIR}/.env.example" "${WEB_DIR}/.env"
  echo "Created ${WEB_DIR}/.env"
fi

echo ""
bash "${SCRIPT_DIR}/ecosystem-status.sh"

echo ""
echo "=== Run apps ==="
APP_URL="${SIKA_APP_URL}"
WEB_URL="${SIKA_CHAIN_WEB_URL}"
if curl -sf -o /dev/null -w "" "${APP_URL}/" 2>/dev/null; then
  echo "  Sika App already running at ${APP_URL}"
else
  echo "  Sika App:  ${SCRIPT_DIR}/start-app.sh"
fi
if curl -sf -o /dev/null -w "" "${WEB_URL}/" 2>/dev/null; then
  echo "  SikaChain site already running at ${WEB_URL}"
else
  echo "  Website:   ${SCRIPT_DIR}/start-web.sh"
  echo "  Or:        cd \"${WEB_DIR}\" && npm run dev"
fi
