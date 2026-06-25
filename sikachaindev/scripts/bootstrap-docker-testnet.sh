#!/usr/bin/env bash
# Local docker testnet: start nodeos as genesis `sikaio`, bootstrap contracts + BPs.
#
# Usage:
#   RPC_HOST_PORT=18890 bash sikachaindev/scripts/bootstrap-docker-testnet.sh
#   RESET=1 bash ...   # wipe docker volume and recreate chain
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPLOY="${ROOT}/deploy/testnet"
GENESIS="${ROOT}/config/testnet/generated/genesis.json"
README="${ROOT}/config/testnet/generated/README.txt"
PRODUCERS="${ROOT}/config/testnet/generated/producers-6.json"
RPC_PORT="${RPC_HOST_PORT:-18890}"
NODE_URL="http://127.0.0.1:${RPC_PORT}"

read_genesis_key() {
  if [[ -f "${README}" ]]; then
    grep '^Genesis private:' "${README}" | awk '{print $3}'
    return 0
  fi
  echo "error: missing ${README} — run bash scripts/gen-testnet-keys.sh" >&2
  exit 1
}

read_genesis_pub_eos() {
  python3 -c "import json; print(json.load(open('${GENESIS}'))['initial_key'])"
}

echo "=== bootstrap-docker-testnet ==="
echo "  NODE_URL=${NODE_URL}"
echo ""

[[ -f "${GENESIS}" && -f "${PRODUCERS}" ]] || {
  echo "error: run bash scripts/gen-testnet-keys.sh first" >&2
  exit 1
}

GENESIS_PVT="$(read_genesis_key)"
GENESIS_PUB_K1="$(node "${SCRIPT_DIR}/lib/key-format.mjs" to-pub-k1 "$(read_genesis_pub_eos)")"
export SIGNATURE_PROVIDER="${GENESIS_PUB_K1}=KEY:${GENESIS_PVT}"
export SIKA_SYSTEM_PRIVATE_KEY="${GENESIS_PVT}"

if [[ "${RESET:-0}" == "1" ]]; then
  echo "--- Reset docker volume ---"
  cd "${DEPLOY}"
  docker compose --env-file .env down -v 2>/dev/null || true
fi

P2P_PORT="${P2P_HOST_PORT:-$((RPC_PORT == 8888 ? 9876 : RPC_PORT + 100))}"
SHIP_PORT="${SHIP_HOST_PORT:-$((RPC_PORT == 8888 ? 8080 : RPC_PORT - 800))}"
# Write bootstrap-phase .env (produce as sikaio until BPs exist)
cat > "${DEPLOY}/.env.bootstrap" <<EOF
SIKA_NODEOS_IMAGE=ghcr.io/rroland10/sikachain-nodeos:sikachain-dev-sika-v5
SIKA_GENESIS_HOST=${GENESIS}
RPC_HOST_PORT=${RPC_PORT}
P2P_HOST_PORT=${P2P_PORT}
SHIP_HOST_PORT=${SHIP_PORT}
PRODUCER_NAME=sikaio
SIGNATURE_PROVIDER=${SIGNATURE_PROVIDER}
P2P_ADVERTISE=127.0.0.1:${P2P_PORT}
P2P_PEERS=
CORS_ORIGIN=*
AGENT_NAME=sikachain-testnet-genesis
EOF

echo "--- Start nodeos (producer=sikaio) ---"
cd "${DEPLOY}"
RPC_HOST_PORT="${RPC_PORT}" \
  P2P_HOST_PORT="$(grep P2P_HOST_PORT .env.bootstrap | cut -d= -f2)" \
  SHIP_HOST_PORT="$(grep SHIP_HOST_PORT .env.bootstrap | cut -d= -f2)" \
  docker compose --env-file .env.bootstrap up -d --no-build

echo "Waiting for block production..."
for _ in $(seq 1 90); do
  if curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null 2>&1; then
    head="$(curl -sf "${NODE_URL}/v1/chain/get_info" | python3 -c "import sys,json; print(json.load(sys.stdin)['head_block_num'])")"
    if [[ "${head}" -gt 5 ]]; then
      echo "  ok  head_block=${head}"
      break
    fi
  fi
  sleep 2
done
if [[ "${head:-0}" -le 5 ]]; then
  echo "error: blocks not advancing — check docker logs (enable-stale-production?)" >&2
  exit 1
fi

bash "${SCRIPT_DIR}/cleos.sh" wallet import --private-key "${GENESIS_PVT}" 2>/dev/null || true

echo ""
echo "--- bootstrap-testnet ---"
SKIP_SCHEDULE="${SKIP_SCHEDULE:-1}" \
SKIP_BP_VOTE="${SKIP_BP_VOTE:-1}" \
PRODUCERS_JSON="${PRODUCERS_JSON:-${PRODUCERS}}" NODE_URL="${NODE_URL}" \
  SIKA_SYSTEM_PRIVATE_KEY="${SIKA_SYSTEM_PRIVATE_KEY:-}" \
  bash "${SCRIPT_DIR}/bootstrap-testnet.sh"

echo ""
echo "--- dev accounts ---"
export SKIP_BP_VOTE=1
bash "${SCRIPT_DIR}/create-dev-accounts.sh"

echo ""
echo "=== bootstrap-docker-testnet complete ==="
echo "  chain_id=$(curl -sf "${NODE_URL}/v1/chain/get_info" | python3 -c 'import json,sys; print(json.load(sys.stdin)["chain_id"])')"
echo "  RPC: ${NODE_URL}"
echo "  Producer: sika (single-node; BPs registered but schedule not activated)"
echo "  Multinode rotation: bash scripts/start-6bp-cluster.sh after copying chain data"
echo "  Hyperion (optional): bash scripts/setup-hyperion-testnet-local.sh  # :7002"
