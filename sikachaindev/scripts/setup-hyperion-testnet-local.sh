#!/usr/bin/env bash
# Hyperion for local docker testnet — reuses dev ES/Rabbit/Mongo on network `hyperion`.
#
# Indexes SHIP from docker nodeos (default RPC :18890, SHIP :18090).
# API listens on :7002 (dev Hyperion stays on :7001).
#
# Usage:
#   bash scripts/setup-hyperion-testnet-local.sh
#   RPC_HOST_PORT=18890 SHIP_HOST_PORT=18090 bash scripts/setup-hyperion-testnet-local.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HYPERION_DIR="${HYPERION_DIR:-${ROOT}/hyperion/hyperion-history-api}"
COMPOSE="${ROOT}/deploy/testnet/docker-compose.hyperion-local.yml"
RPC_PORT="${RPC_HOST_PORT:-18890}"
SHIP_PORT="${SHIP_HOST_PORT:-$((RPC_PORT - 800))}"
NODE_URL="http://127.0.0.1:${RPC_PORT}"
HYPERION_PORT="${HYPERION_PORT:-7002}"

echo "=== setup-hyperion-testnet-local ==="
echo "  RPC=${NODE_URL}  SHIP=ws://127.0.0.1:${SHIP_PORT}  API=:${HYPERION_PORT}"
echo ""

curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null || {
  echo "error: testnet RPC not reachable — run bootstrap-docker-testnet.sh first" >&2
  exit 1
}

TESTNET_CHAIN_ID="$(curl -sf "${NODE_URL}/v1/chain/get_info" | python3 -c 'import json,sys; print(json.load(sys.stdin)["chain_id"])')"
export TESTNET_CHAIN_ID
export TESTNET_RPC_URL="${NODE_URL}"
export TESTNET_SHIP_URL="ws://127.0.0.1:${SHIP_PORT}"
export HYPERION_PORT
export HYPERION_DOCKER=1

if [[ ! -f "${HYPERION_DIR}/package.json" ]]; then
  echo "Cloning hyperion-history-api..."
  git clone --depth 1 --branch main https://github.com/eosrio/hyperion-history-api "${HYPERION_DIR}"
fi

if ! docker network inspect hyperion >/dev/null 2>&1; then
  echo "Starting Hyperion backing services..."
  bash "${SCRIPT_DIR}/start-hyperion-deps.sh"
elif ! docker ps --format '{{.Names}}' | grep -q '^hyperion-elasticsearch-1$'; then
  echo "Restarting Hyperion backing services (elasticsearch not running)..."
  bash "${SCRIPT_DIR}/start-hyperion-deps.sh"
fi

node "${SCRIPT_DIR}/configure-hyperion-testnet.mjs" --docker --merge

echo ""
echo "Starting testnet Hyperion indexer + API..."
docker compose -f "${COMPOSE}" up -d --build

echo ""
echo "Waiting for Hyperion testnet API..."
for _ in $(seq 1 60); do
  if curl -sf "http://127.0.0.1:${HYPERION_PORT}/v2/health" >/dev/null 2>&1; then
    echo "  ok  http://127.0.0.1:${HYPERION_PORT}/v2/health"
    break
  fi
  sleep 2
done

echo ""
HYPERION_URL="http://127.0.0.1:${HYPERION_PORT}" \
  HYPERION_PROBE_ACCOUNT=sikadev \
  bash "${SCRIPT_DIR}/check-hyperion.sh" || {
  echo "  note: indexer may still be catching up — retry check-hyperion in ~1 min"
}

echo ""
echo "=== testnet Hyperion ready ==="
echo "  HYPERION_URL=http://127.0.0.1:${HYPERION_PORT}"
echo "  App env: TESTNET_HYPERION_URL=http://127.0.0.1:${HYPERION_PORT} APPLY=1 bash scripts/sync-testnet-app-env.sh"
