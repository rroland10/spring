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

ENV_SRC="${APP_DIR}/.env.sikachaindev"
if [[ "${SIKACHAIN_DEV:-}" == "1" ]] && [[ -f "${APP_DIR}/.env.sikachaindev.phase3" ]]; then
  ENV_SRC="${APP_DIR}/.env.sikachaindev.phase3"
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
