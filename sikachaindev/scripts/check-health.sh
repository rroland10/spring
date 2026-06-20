#!/usr/bin/env bash
# Exit 0 when SikaChainDev RPC responds and SIKA token is funded.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

FAIL=0

check() {
  local label="$1"
  shift
  if "$@"; then
    echo "  ok  ${label}"
  else
    echo "  FAIL ${label}"
    FAIL=1
  fi
}

echo "=== SikaChainDev health ==="

set +e
check "nodeos RPC" bash -c "curl -sf \"${NODE_URL}/v1/chain/get_info\" >/dev/null"
check "keosd wallet" bash -c "curl -sf \"${WALLET_URL}/v1/wallet/list_wallets\" >/dev/null"
check "SIKA token funded" bash -c "
  \"${CLEOS}\" --url \"${NODE_URL}\" get currency stats sika.token SIKA 2>/dev/null \
    | python3 -c \"import json,sys; d=json.load(sys.stdin); s=d.get('SIKA',{}).get('supply','0').split()[0]; sys.exit(0 if float(s)>0 else 1)\"
"
check "sikadev account" bash -c "
  curl -sf \"${NODE_URL}/v1/chain/get_account\" \
    -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"sikadev\"}' | grep -q '\"account_name\"'
"
set -e

if curl -sf -o /dev/null "${SIKA_APP_URL}/" 2>/dev/null; then
  echo "  ok  Sika app (${SIKA_APP_URL})"
else
  echo "  --  Sika app not on ${SIKA_APP_URL} (optional)"
fi

exit "${FAIL}"
