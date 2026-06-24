#!/usr/bin/env bash
# Sync Sika app .env.local for local docker testnet (:18890).
#
# Usage:
#   RPC_HOST_PORT=18890 bash scripts/sync-testnet-app-env.sh
#   APPLY=1 bash scripts/sync-testnet-app-env.sh   # copy → Sika app/.env.local
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
RPC_PORT="${RPC_HOST_PORT:-18890}"
HYPERION_PORT="${HYPERION_PORT:-7002}"
NODE_URL="http://127.0.0.1:${RPC_PORT}"
HYPERION_URL="http://127.0.0.1:${HYPERION_PORT}"
OUT="${APP_DIR}/.env.testnet-local"

chain_id="$(curl -sf "${NODE_URL}/v1/chain/get_info" | python3 -c 'import json,sys; print(json.load(sys.stdin)["chain_id"])')"

TESTNET_CHAIN_ID="${chain_id}" \
TESTNET_RPC_URL="${NODE_URL}" \
TESTNET_HYPERION_URL="${HYPERION_URL}" \
TESTNET_APP_URL="http://127.0.0.1:${SIKA_APP_PORT:-3003}" \
TESTNET_CHAIN_NAME="SikaChain Testnet (local docker)" \
  node "${SCRIPT_DIR}/export-testnet-env.mjs" "${OUT}"

{
  echo ""
  echo "# Local docker testnet — dev wallet for Playwright / cleos parity"
  echo "NEXT_PUBLIC_DEV_WALLET=1"
  echo "NEXT_PUBLIC_CHAIN_RPC_PROTOCOL=http"
  echo "NEXT_PUBLIC_CHAIN_RPC_HOST=127.0.0.1"
  echo "NEXT_PUBLIC_CHAIN_RPC_PORT=${RPC_PORT}"
  echo "NEXT_PUBLIC_EOS_RPC_PROTOCOL=http"
  echo "NEXT_PUBLIC_EOS_RPC_HOST=127.0.0.1"
  echo "NEXT_PUBLIC_EOS_RPC_PORT=${RPC_PORT}"
  echo "NEXT_PUBLIC_EOS_READ_RPC_URLS=${NODE_URL}"
  echo "NEXT_PUBLIC_EOS_CHAIN_ID=${chain_id}"
  echo "NEXT_PUBLIC_EOS_NAME=SikaChain Testnet"
} >> "${OUT}"

echo "Wrote ${OUT}"

if [[ "${APPLY:-0}" == "1" ]]; then
  cp "${OUT}" "${APP_DIR}/.env.local"
  echo "Applied → ${APP_DIR}/.env.local (restart app: bash scripts/start-app.sh)"
fi
