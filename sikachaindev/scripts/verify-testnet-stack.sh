#!/usr/bin/env bash
# Full local docker testnet gate — run after bootstrap-docker-testnet.sh (+ optional Hyperion).
#
# Usage:
#   bash scripts/verify-testnet-stack.sh
#   NODE_URL=http://127.0.0.1:18890 HYPERION_URL=http://127.0.0.1:7002 bash scripts/verify-testnet-stack.sh
#   QUICK=1 bash scripts/verify-testnet-stack.sh   # skip slow cleos matrix
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RPC_PORT="${RPC_HOST_PORT:-18890}"
# Always target docker testnet RPC for this gate (override inherited dev NODE_URL).
export NODE_URL="http://127.0.0.1:${RPC_PORT}"
export HYPERION_URL="${HYPERION_URL:-http://127.0.0.1:7002}"

source "${SCRIPT_DIR}/env.sh"
export NODE_URL="http://127.0.0.1:${RPC_PORT}"
README="${ROOT}/config/testnet/generated/README.txt"
FAIL=0

if [[ -f "${README}" ]]; then
  GENESIS_PVT="$(grep '^Genesis private:' "${README}" | awk '{print $3}')"
  export SIKA_SYSTEM_PRIVATE_KEY="${SIKA_SYSTEM_PRIVATE_KEY:-${GENESIS_PVT}}"
fi

export SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT:-sika}"
export SKIP_BP_VOTE=1

chain_id="$(curl -sf "${NODE_URL}/v1/chain/get_info" | python3 -c 'import json,sys; print(json.load(sys.stdin)["chain_id"])')"
EXPECT_CHAIN_ID="${EXPECT_CHAIN_ID:-${chain_id}}"

echo "=== verify-testnet-stack ==="
echo "  NODE_URL=${NODE_URL}"
echo "  chain_id=${chain_id}"
echo "  HYPERION_URL=${HYPERION_URL}"
echo ""

run() {
  local label="$1"
  shift
  printf "  %-44s " "${label}"
  if "$@"; then
    echo "ok"
  else
    echo "FAIL"
    FAIL=1
  fi
}

run "verify-testnet.sh" \
  env NODE_URL="${NODE_URL}" EXPECT_CHAIN_ID="${EXPECT_CHAIN_ID}" HYPERION_URL="${HYPERION_URL}" \
    bash "${SCRIPT_DIR}/verify-testnet.sh"

if [[ "${QUICK:-0}" != "1" ]]; then
  run "test-cleos.sh" \
    env NODE_URL="${NODE_URL}" SIKA_SYSTEM_PRIVATE_KEY="${SIKA_SYSTEM_PRIVATE_KEY:-}" \
      bash "${SCRIPT_DIR}/test-cleos.sh"
  run "test-app-cleos-full.sh" \
    env NODE_URL="${NODE_URL}" SIKA_SYSTEM_PRIVATE_KEY="${SIKA_SYSTEM_PRIVATE_KEY:-}" SKIP_BP_VOTE=1 \
      bash "${SCRIPT_DIR}/test-app-cleos-full.sh"
fi

run "test-features.sh" \
  env NODE_URL="${NODE_URL}" SKIP_BP_VOTE=1 \
    bash "${SCRIPT_DIR}/test-features.sh"

run "export-testnet-client-config" \
  env NODE_URL="${NODE_URL}" TESTNET_HYPERION_URL="${HYPERION_URL}" \
    bash "${SCRIPT_DIR}/export-testnet-client-config.sh" >/dev/null

active="$(curl -sf "${NODE_URL}/v1/chain/get_producer_schedule" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(','.join(p['producer_name'] for p in d.get('active',{}).get('producers',[])))
")"
if [[ "${active}" == "sika" ]]; then
  echo "  ok  single-node schedule (producer=sika)"
else
  echo "  WARN active schedule: ${active} (single-node may stall LIB)" >&2
fi

echo ""
if [[ "${FAIL}" -eq 0 ]]; then
  echo "=== verify-testnet-stack complete — ready for hosted deploy ==="
  echo ""
  echo "Hosted next steps:"
  echo "  1. bash deploy/testnet/pull-image.sh"
  echo "  2. Fly: cp deploy/testnet/fly.toml.example fly.toml && fly deploy"
  echo "  3. NODE_URL=https://<rpc> bash scripts/bootstrap-testnet.sh  (SKIP_BP_VOTE=1 for single BP)"
  echo "  4. bash scripts/setup-hyperion-testnet.sh"
  echo "  5. bash scripts/verify-predeploy-remote.sh"
else
  echo "=== verify-testnet-stack FAILED ===" >&2
  exit 1
fi
