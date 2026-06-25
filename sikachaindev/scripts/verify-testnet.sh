#!/usr/bin/env bash
# Smoke a hosted SikaChain testnet (protocol sikaio + system sika + sika.token + Hyperion).
#
# Usage:
#   NODE_URL=https://rpc.testnet.sikachain.gh bash scripts/verify-testnet.sh
#   NODE_URL=... HYPERION_URL=https://hyperion.testnet.sikachain.gh bash scripts/verify-testnet.sh
#   NODE_URL=... EXPECT_CHAIN_ID=abc... bash scripts/verify-testnet.sh
#
# Optional:
#   VERIFY_CLEOS=0     skip on-chain cleos transfers/msig
#   SIKACHAIN_DEV=1    run verify-phase3 checks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

if [[ -z "${NODE_URL:-}" ]]; then
  echo "error: set NODE_URL to the public HTTPS RPC (e.g. https://rpc.testnet.sikachain.gh)"
  exit 1
fi

export SIKACHAIN_DEV="${SIKACHAIN_DEV:-1}"
export SIKA_PROTOCOL_ACCOUNT="${SIKA_PROTOCOL_ACCOUNT:-sikaio}"
export SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT:-sika}"
export WALLET_URL="${WALLET_URL:-}" # cleos wallet not required unless VERIFY_CLEOS=1

echo "=== verify-testnet ==="
echo "  NODE_URL=${NODE_URL}"
echo "  HYPERION_URL=${HYPERION_URL:-<unset>}"
echo "  EXPECT_CHAIN_ID=${EXPECT_CHAIN_ID:-<any>}"
echo ""

bash "${SCRIPT_DIR}/wait-for-rpc.sh" 120

info="$(curl -sf "${NODE_URL}/v1/chain/get_info")"
chain_id="$(echo "${info}" | python3 -c "import json,sys; print(json.load(sys.stdin)['chain_id'])")"
head="$(echo "${info}" | python3 -c "import json,sys; print(json.load(sys.stdin)['head_block_num'])")"
echo "  chain_id=${chain_id}"
echo "  head_block=${head}"

if [[ -n "${EXPECT_CHAIN_ID:-}" && "${chain_id}" != "${EXPECT_CHAIN_ID}" ]]; then
  echo "error: chain_id mismatch (expected ${EXPECT_CHAIN_ID})"
  exit 1
fi

FAIL=0
check() {
  local label="$1"
  shift
  if "$@"; then
    echo "  ok  ${label}"
  else
    echo "  FAIL ${label}" >&2
    FAIL=1
  fi
}

check "sikaio account exists (protocol)" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_account' -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"sikaio\"}' | grep -q '\"privileged\":true'
"

check "sika account exists (system contract)" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_account' -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"sika\"}' | grep -q '\"privileged\":true'
"

check "eosio account absent (legacy)" bash -c "
  ! curl -sf '${NODE_URL}/v1/chain/get_account' -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"eosio\"}' | grep -q account_name
"

check "sika.token SIKA supply" bash -c "
  \"${CLEOS}\" --url \"${NODE_URL}\" get currency stats sika.token SIKA 2>/dev/null \
    | python3 -c \"import json,sys; d=json.load(sys.stdin); s=d.get('SIKA',{}).get('supply','0').split()[0]; sys.exit(0 if float(s)>0 else 1)\"
"

check "sika.token CGHS listed" bash -c "
  \"${CLEOS}\" --url \"${NODE_URL}\" get currency stats sika.token CGHS 2>/dev/null \
    | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'CGHS' in d else 1)\"
"

check "cleos get account sika (sika.token)" bash -c "
  \"${CLEOS}\" --url \"${NODE_URL}\" get account sika 2>&1 | grep -q 'SIKA balances'
"

if [[ -n "${HYPERION_URL:-}" ]]; then
  HYPERION_URL="${HYPERION_URL%/}"
  export HYPERION_URL
  bash "${SCRIPT_DIR}/check-hyperion.sh"
else
  echo "  -- Hyperion skipped (set HYPERION_URL to probe history)"
fi

if [[ "${SIKACHAIN_DEV:-}" == "1" ]]; then
  bash "${SCRIPT_DIR}/verify-phase3.sh"
fi

if [[ "${VERIFY_CLEOS:-0}" == "1" ]]; then
  if [[ -z "${WALLET_URL:-}" ]]; then
    echo "error: VERIFY_CLEOS=1 requires local keosd (WALLET_URL)"
    exit 1
  fi
  bash "${SCRIPT_DIR}/test-cleos.sh"
fi

if [[ "${FAIL}" -ne 0 ]]; then
  echo "=== verify-testnet FAILED ===" >&2
  exit 1
fi

echo ""
echo "=== verify-testnet complete ==="
echo "  Next: publish anchor-chain JSON and wallet env (see docs/testnet-deploy.md)"
