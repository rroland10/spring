#!/usr/bin/env bash
# Start testnet BP1 via docker compose (local dry-run or VPS).
#
# Prereqs:
#   bash sikachaindev/scripts/gen-testnet-keys.sh
#   bash sikachaindev/deploy/testnet/pull-image.sh   # after GHCR image exists
#
# Usage:
#   bash sikachaindev/deploy/testnet/up.sh
#   SIKA_GENESIS_HOST=../../config/testnet/generated/genesis.json bash ...
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GENESIS_HOST="${SIKA_GENESIS_HOST:-${ROOT}/config/testnet/generated/genesis.json}"
PRODUCERS="${PRODUCERS_JSON:-${ROOT}/config/testnet/generated/producers-6.json}"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "${GENESIS_HOST}" ]]; then
  echo "error: missing genesis — run: bash scripts/gen-testnet-keys.sh"
  echo "  expected: ${GENESIS_HOST}"
  exit 1
fi

if [[ ! -f "${PRODUCERS}" ]]; then
  echo "error: missing producers file: ${PRODUCERS}"
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Creating ${ENV_FILE} from .env.example..."
  cp "${SCRIPT_DIR}/.env.example" "${ENV_FILE}"
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

if [[ "${SIGNATURE_PROVIDER:-}" == *REPLACE* ]] || [[ -z "${SIGNATURE_PROVIDER:-}" ]]; then
  read -r pub_eos pvt < <(python3 - <<'PY' "${PRODUCERS}" "${PRODUCER_NAME:-sikabpa}"
import json, sys
path, name = sys.argv[1:3]
for p in json.load(open(path))["producers"]:
    if p["name"] == name:
        print(p["pub"], p["pvt"])
        break
else:
    raise SystemExit(f"producer {name} not in {path}")
PY
)
  pub_k1="$(node "${ROOT}/scripts/lib/key-format.mjs" to-pub-k1 "${pub_eos}")"
  export SIGNATURE_PROVIDER="${pub_k1}=KEY:${pvt}"
  if grep -q '^SIGNATURE_PROVIDER=.*REPLACE' "${ENV_FILE}" 2>/dev/null || ! grep -q '^SIGNATURE_PROVIDER=' "${ENV_FILE}"; then
    if grep -q '^SIGNATURE_PROVIDER=' "${ENV_FILE}"; then
      if [[ "$(uname -s)" == Darwin ]]; then
        sed -i '' "s|^SIGNATURE_PROVIDER=.*|SIGNATURE_PROVIDER=${SIGNATURE_PROVIDER}|" "${ENV_FILE}"
      else
        sed -i "s|^SIGNATURE_PROVIDER=.*|SIGNATURE_PROVIDER=${SIGNATURE_PROVIDER}|" "${ENV_FILE}"
      fi
    else
      echo "SIGNATURE_PROVIDER=${SIGNATURE_PROVIDER}" >> "${ENV_FILE}"
    fi
  fi
  echo "Set SIGNATURE_PROVIDER for ${PRODUCER_NAME:-sikabpa} in .env"
fi

export SIKA_GENESIS_HOST="${GENESIS_HOST}"

echo "=== testnet docker up ==="
  echo "  image: ${SIKA_NODEOS_IMAGE:-ghcr.io/rroland10/sikachain-nodeos:sikachain-dev-sika-v5}"
echo "  genesis: ${GENESIS_HOST}"
echo "  producer: ${PRODUCER_NAME:-sikabpa}"
echo "  RPC: http://127.0.0.1:${RPC_HOST_PORT:-8888}"
echo ""

cd "${SCRIPT_DIR}"
RPC_HOST_PORT="${RPC_HOST_PORT:-8888}" docker compose --env-file "${ENV_FILE}" up -d --no-build

RPC_URL="http://127.0.0.1:${RPC_HOST_PORT:-8888}"
echo ""
echo "Waiting for RPC at ${RPC_URL}..."
for _ in $(seq 1 60); do
  if curl -sf "${RPC_URL}/v1/chain/get_info" >/dev/null 2>&1; then
  chain_id="$(curl -sf "${RPC_URL}/v1/chain/get_info" | python3 -c "import sys,json; print(json.load(sys.stdin)['chain_id'])")"
    echo "  ok  RPC up — chain_id=${chain_id}"
    echo ""
    echo "Next:"
    echo "  cleos wallet import --private-key <genesis key from config/testnet/generated/README.txt>"
    echo "  PRODUCERS_JSON=${PRODUCERS} NODE_URL=${RPC_URL} bash scripts/bootstrap-testnet.sh"
    exit 0
  fi
  sleep 2
done

echo "error: RPC not ready after 120s — docker compose logs nodeos" >&2
exit 1
