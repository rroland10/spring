#!/usr/bin/env bash
# Wallet UI RPC smoke — probes tables/endpoints the Sika app reads (Phase 3 / sika system).
#
# Usage:
#   export SIKACHAIN_DEV=1 SIKA_SYSTEM_ACCOUNT=sika
#   bash scripts/smoke-wallet.sh [account]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

DEV_ACCOUNT="${1:-sikadev}"
SYS="${SIKA_SYSTEM_ACCOUNT:-sika}"
TOKEN="${SIKA_TOKEN_CONTRACT:-sika.token}"
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

echo "=== Wallet RPC smoke (${DEV_ACCOUNT}, system=${SYS}) ==="
bash "${SCRIPT_DIR}/wait-for-rpc.sh" 60

check "${DEV_ACCOUNT} account" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_account' \
    -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"${DEV_ACCOUNT}\"}' | grep -q account_name
"

check "SIKA balance" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_currency_balance' \
    -H 'Content-Type: application/json' \
    -d '{\"code\":\"${TOKEN}\",\"account\":\"${DEV_ACCOUNT}\",\"symbol\":\"SIKA\"}' \
    | python3 -c \"import json,sys; b=json.load(sys.stdin); sys.exit(0 if b and float(b[0].split()[0])>0 else 1)\"
"

check "CGHS balance" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_currency_balance' \
    -H 'Content-Type: application/json' \
    -d '{\"code\":\"${TOKEN}\",\"account\":\"${DEV_ACCOUNT}\",\"symbol\":\"CGHS\"}' \
    | python3 -c \"import json,sys; b=json.load(sys.stdin); sys.exit(0 if b and float(b[0].split()[0])>0 else 1)\"
"

check "delband (@${SYS})" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_table_rows' \
    -H 'Content-Type: application/json' \
    -d '{\"json\":true,\"code\":\"${SYS}\",\"scope\":\"${DEV_ACCOUNT}\",\"table\":\"delband\",\"limit\":10}' \
    | python3 -c \"import json,sys; json.load(sys.stdin); sys.exit(0)\"
"

check "rexbal (@${SYS})" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_table_rows' \
    -H 'Content-Type: application/json' \
    -d '{\"json\":true,\"code\":\"${SYS}\",\"scope\":\"${SYS}\",\"table\":\"rexbal\",\"lower_bound\":\"${DEV_ACCOUNT}\",\"upper_bound\":\"${DEV_ACCOUNT}\",\"limit\":1}' \
    | python3 -c \"import json,sys; json.load(sys.stdin); sys.exit(0)\"
"

check "voters (@${SYS})" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_table_rows' \
    -H 'Content-Type: application/json' \
    -d '{\"json\":true,\"code\":\"${SYS}\",\"scope\":\"${SYS}\",\"table\":\"voters\",\"lower_bound\":\"${DEV_ACCOUNT}\",\"upper_bound\":\"${DEV_ACCOUNT}\",\"limit\":1}' \
    | python3 -c \"import json,sys; json.load(sys.stdin); sys.exit(0)\"
"

if curl -sf "${NODE_URL}/v1/chain/get_code" \
  -H 'Content-Type: application/json' \
  -d '{"account_name":"atomicassets"}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('wasm') else 1)" 2>/dev/null; then
  check "NFT assets (atomicassets)" bash -c "
    curl -sf '${NODE_URL}/v1/chain/get_table_rows' \
      -H 'Content-Type: application/json' \
      -d '{\"json\":true,\"code\":\"atomicassets\",\"scope\":\"${DEV_ACCOUNT}\",\"table\":\"assets\",\"limit\":1}' \
      | python3 -c \"import json,sys; json.load(sys.stdin); sys.exit(0)\"
  "
else
  echo "  --  atomicassets not deployed (optional)"
fi

if [[ "${FAIL}" -eq 0 ]]; then
  echo "=== smoke-wallet complete — wallet RPC probes passed ==="
else
  echo "=== smoke-wallet failed ===" >&2
  exit 1
fi
