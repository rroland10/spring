#!/usr/bin/env bash
# Sync SikaChainDev env and start the Next.js wallet on SIKA_APP_PORT (default 3003).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "error: Sika app not found at ${APP_DIR}"
  echo "  set SIKA_APP_DIR=/path/to/Sika\\ app"
  exit 1
fi

if [[ ! -f "${APP_DIR}/package.json" ]]; then
  echo "error: ${APP_DIR} is not the Sika app (no package.json)"
  exit 1
fi

bash "${SCRIPT_DIR}/sync-dev-env.sh" 2>/dev/null || true

if [[ "${TESTNET_LOCAL:-0}" == "1" ]]; then
  ENV_SRC="${APP_DIR}/.env.testnet-local"
  if [[ ! -f "${ENV_SRC}" ]]; then
    APPLY=1 RPC_HOST_PORT="${RPC_HOST_PORT:-18890}" bash "${SCRIPT_DIR}/sync-testnet-app-env.sh"
    ENV_SRC="${APP_DIR}/.env.testnet-local"
  fi
elif [[ "${SIKACHAIN_DEV:-}" == "1" ]] && [[ -f "${APP_DIR}/.env.sikachaindev.phase3" ]]; then
  ENV_SRC="${APP_DIR}/.env.sikachaindev.phase3"
else
  ENV_SRC="${APP_DIR}/.env.sikachaindev"
fi

if [[ -f "${ENV_SRC}" ]]; then
  cp "${ENV_SRC}" "${APP_DIR}/.env.local"
  echo "Synced ${APP_DIR}/.env.local"
else
  echo "warning: ${ENV_SRC} missing — using app defaults"
fi

if curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null 2>&1; then
  echo "Chain RPC ok at ${NODE_URL}"
else
  echo "warning: chain not reachable at ${NODE_URL}"
  echo "  start in another terminal: ${SCRIPT_DIR}/start-all.sh"
fi

echo ""
echo "Starting Sika app → ${SIKA_APP_URL}"
echo "  (port ${SIKA_APP_PORT}; not :3000)"
echo ""

cd "${APP_DIR}"
exec npm run dev
