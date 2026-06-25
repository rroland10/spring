#!/usr/bin/env bash
# Configure and start Hyperion for a hosted SikaChain testnet.
#
# Prerequisites:
#   - nodeos exposing RPC + SHIP (state_history_plugin)
#   - Docker
#
# Usage:
#   TESTNET_CHAIN_ID=... \
#   TESTNET_RPC_URL=https://rpc.testnet.sikachain.gh \
#   TESTNET_SHIP_URL=ws://bp1.testnet.sikachain.gh:8080 \
#   bash scripts/setup-hyperion-testnet.sh
#
# Options:
#   HYPERION_START=0   config only, do not docker compose up
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HYPERION_DIR="${HYPERION_DIR:-${ROOT}/hyperion/hyperion-history-api}"
COMPOSE="${ROOT}/deploy/testnet/docker-compose.hyperion.yml"

: "${TESTNET_CHAIN_ID:?set TESTNET_CHAIN_ID}"
: "${TESTNET_RPC_URL:?set TESTNET_RPC_URL}"
: "${TESTNET_SHIP_URL:?set TESTNET_SHIP_URL}"

if [[ ! -f "${HYPERION_DIR}/package.json" ]]; then
  echo "Cloning hyperion-history-api..."
  git clone --depth 1 --branch main https://github.com/eosrio/hyperion-history-api "${HYPERION_DIR}"
fi

export HYPERION_DOCKER=1
node "${SCRIPT_DIR}/configure-hyperion-testnet.mjs" --docker

if [[ "${HYPERION_START:-1}" == "1" ]]; then
  echo ""
  echo "Starting Hyperion stack..."
  docker compose -f "${COMPOSE}" up -d --build
  echo ""
  echo "Hyperion API: http://127.0.0.1:${HYPERION_PORT:-7001}/v2/health"
  echo "Verify: HYPERION_URL=http://127.0.0.1:${HYPERION_PORT:-7001} bash scripts/check-hyperion.sh"
fi
