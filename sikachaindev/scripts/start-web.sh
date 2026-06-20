#!/usr/bin/env bash
# Start the SikaChain GTM marketing site on SIKA_CHAIN_WEB_PORT (default 3004).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

WEB_DIR="${SIKA_CHAIN_WEB_DIR}"

if [[ ! -d "${WEB_DIR}" ]]; then
  echo "error: SikaChain site not found at ${WEB_DIR}"
  echo "  set SIKA_CHAIN_WEB_DIR=/path/to/SikaChain"
  exit 1
fi

if [[ ! -f "${WEB_DIR}/package.json" ]]; then
  echo "error: ${WEB_DIR} is not the SikaChain site (no package.json)"
  exit 1
fi

if [[ ! -f "${WEB_DIR}/.env" ]] && [[ -f "${WEB_DIR}/.env.example" ]]; then
  cp "${WEB_DIR}/.env.example" "${WEB_DIR}/.env"
  echo "Created ${WEB_DIR}/.env from .env.example"
fi

if curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null 2>&1; then
  echo "Chain RPC ok at ${NODE_URL}"
else
  echo "warning: chain not reachable at ${NODE_URL}"
  echo "  start in another terminal: ${SCRIPT_DIR}/start-all.sh"
fi

echo ""
echo "Starting SikaChain site → ${SIKA_CHAIN_WEB_URL}"
echo "  explorer: ${SIKA_CHAIN_WEB_URL}/explorer"
echo "  apply:    ${SIKA_CHAIN_WEB_URL}/apply"
echo ""

cd "${WEB_DIR}"
exec npm run dev
