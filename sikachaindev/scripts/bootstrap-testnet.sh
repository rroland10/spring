#!/usr/bin/env bash
# Bootstrap sika.* contracts + BPs on a **fresh testnet** (not SikaChainDev mirror).
#
# Prerequisites:
#   - nodeos built from sikachain-dev-sika-v2+ with -DSIKACHAIN=ON
#   - Fresh genesis (new keys) — see docs/testnet-bootstrap.md
#   - Genesis `sika` active key in keosd (or cleos wallet)
#   - Contracts built: SIKACHAIN=1 ./build.sh (sikachain sys contract)
#
# Usage (from ops machine with wallet access):
#   NODE_URL=https://rpc.testnet.sikachain.gh \
#   WALLET_URL=http://127.0.0.1:8899 \
#   bash scripts/bootstrap-testnet.sh
#
# Options:
#   BP_COUNT=6|21          default 6
#   PRODUCERS_JSON=...     BP keys file (generate new keys for testnet!)
#   DEPLOY_ATOMICASSETS=1  optional NFT contract
#   ALLOW_DEV_CHAIN=1      allow SikaChainDev chain id (local dry-run only)
#   SKIP_BP=1              contracts only, no producer registration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

DEV_CHAIN_ID="9b2fde923758593c09517f77ed445a3962a9c938f44405dac43b4ccfebbfa57e"
BP_COUNT="${BP_COUNT:-6}"

echo "=== bootstrap-testnet ==="
echo "  NODE_URL=${NODE_URL}"
echo "  BP_COUNT=${BP_COUNT}"
echo ""

bash "${SCRIPT_DIR}/wait-for-rpc.sh" 120

chain_id="$(curl -sf "${NODE_URL}/v1/chain/get_info" | python3 -c "import json,sys; print(json.load(sys.stdin)['chain_id'])")"
echo "  chain_id=${chain_id}"

if [[ "${chain_id}" == "${DEV_CHAIN_ID}" && "${ALLOW_DEV_CHAIN:-0}" != "1" ]]; then
  echo "error: chain_id matches SikaChainDev — use bootstrap-dev.sh locally, or ALLOW_DEV_CHAIN=1" >&2
  exit 1
fi

if [[ -z "${SIKA_SYSTEM_PRIVATE_KEY:-}" && -f "${ROOT}/config/testnet/generated/README.txt" ]]; then
  SIKA_SYSTEM_PRIVATE_KEY="$(grep '^Genesis private:' "${ROOT}/config/testnet/generated/README.txt" | awk '{print $3}')"
  export SIKA_SYSTEM_PRIVATE_KEY
fi

export SIKACHAIN_DEV=1
export SIKA_SYSTEM_ACCOUNT=sika

echo ""
echo "--- Wallet ---"
bash "${SCRIPT_DIR}/setup-wallet.sh" 2>/dev/null || {
  echo "  (setup-wallet skipped — ensure sika@active key is imported)"
}

echo ""
echo "--- System contracts ---"
bash "${SCRIPT_DIR}/deploy-sika-system.sh"

if [[ "${SKIP_BP:-0}" != "1" ]]; then
  echo ""
  echo "--- Block producers ---"
  if [[ "${BP_COUNT}" == "21" ]]; then
    export PRODUCERS_JSON="${PRODUCERS_JSON:-${ROOT}/config/producers-21.json}"
    bash "${SCRIPT_DIR}/bootstrap-21bp.sh"
  else
    export PRODUCERS_JSON="${PRODUCERS_JSON:-${ROOT}/config/producers-6.json}"
    SKIP_SCHEDULE="${SKIP_SCHEDULE:-0}" SKIP_BP_VOTE="${SKIP_BP_VOTE:-0}" bash "${SCRIPT_DIR}/bootstrap-6bp.sh"
  fi
fi

echo ""
echo "--- Verify ---"
EXPECT_CHAIN_ID="${chain_id}" \
  HYPERION_URL="${HYPERION_URL:-}" \
  bash "${SCRIPT_DIR}/verify-testnet.sh"

echo ""
echo "=== bootstrap-testnet complete ==="
echo "  Publish client config:"
echo "    TESTNET_CHAIN_ID=${chain_id} TESTNET_RPC_URL=<public-https> node scripts/export-testnet-env.mjs"
echo "    TESTNET_CHAIN_ID=${chain_id} node scripts/export-anchor-chain.mjs --testnet-example"
