#!/usr/bin/env bash
# Exit 0 when SikaChainDev RPC responds and SIKA + CGHS tokens are funded.
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
check "CGHS stablecoin created" bash -c "
  \"${CLEOS}\" --url \"${NODE_URL}\" get currency stats sika.token CGHS 2>/dev/null \
    | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('CGHS',{}).get('max_supply') else 1)\"
"
check "sikadev CGHS balance" bash -c "
  curl -sf \"${NODE_URL}/v1/chain/get_currency_balance\" \
    -H 'Content-Type: application/json' \
    -d '{\"code\":\"sika.token\",\"account\":\"sikadev\",\"symbol\":\"CGHS\"}' \
    | python3 -c \"import json,sys; b=json.load(sys.stdin); sys.exit(0 if b and float(b[0].split()[0])>0 else 1)\"
"
check "sika.msig privileged" bash -c "
  curl -sf \"${NODE_URL}/v1/chain/get_account\" \
    -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"${MSIG_ACCOUNT}\"}' \
    | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('privileged') else 1)\"
"
check "sikadev account" bash -c "
  curl -sf \"${NODE_URL}/v1/chain/get_account\" \
    -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"sikadev\"}' | grep -q '\"account_name\"'
"
check "sikauser1 peer account" bash -c "
  curl -sf \"${NODE_URL}/v1/chain/get_account\" \
    -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"sikauser1\"}' | grep -q '\"account_name\"'
"
check "sikauser2 peer account" bash -c "
  curl -sf \"${NODE_URL}/v1/chain/get_account\" \
    -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"sikauser2\"}' | grep -q '\"account_name\"'
"
check "nodeos RPC CORS (browser)" bash -c "
  curl -sfI -X OPTIONS \"${NODE_URL}/v1/chain/get_info\" \
    -H 'Origin: http://127.0.0.1:3003' \
    -H 'Access-Control-Request-Method: POST' \
    | grep -qi 'access-control-allow-origin'
"

if [[ "${WALLET_READY:-0}" == "1" ]]; then
  check "Hyperion v2 (wallet activity)" bash "${SCRIPT_DIR}/check-hyperion.sh"
fi

if [[ "${SIKACHAIN_DEV:-}" == "1" ]]; then
  check "Phase 3 system (${SIKA_SYSTEM_ACCOUNT}) privileged" bash -c "
    curl -sf \"${NODE_URL}/v1/chain/get_account\" \
      -H 'Content-Type: application/json' \
      -d '{\"account_name\":\"${SIKA_SYSTEM_ACCOUNT}\"}' \
      | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('privileged') else 1)\"
  "
  check "producer in 6-BP set" bash -c "
    head=\$(curl -sf \"${NODE_URL}/v1/chain/get_info\" | python3 -c \"import json,sys; print(json.load(sys.stdin).get('head_block_producer',''))\")
    python3 - <<'PY' \"\${head}\"
import sys
allowed = {'sika','sikabpa','sikabpb','sikabpc','sikabpd','sikabpe','sikabpf'}
sys.exit(0 if sys.argv[1] in allowed else 1)
PY
  "
  check "rammarket table (@${SIKA_SYSTEM_ACCOUNT})" bash -c "
    curl -sf \"${NODE_URL}/v1/chain/get_table_rows\" \
      -H 'Content-Type: application/json' \
      -d '{\"json\":true,\"code\":\"${SIKA_SYSTEM_ACCOUNT}\",\"scope\":\"${SIKA_SYSTEM_ACCOUNT}\",\"table\":\"rammarket\",\"limit\":1}' \
      | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('rows') else 1)\"
  "
  check "rexpool table (@${SIKA_SYSTEM_ACCOUNT})" bash -c "
    curl -sf \"${NODE_URL}/v1/chain/get_table_rows\" \
      -H 'Content-Type: application/json' \
      -d '{\"json\":true,\"code\":\"${SIKA_SYSTEM_ACCOUNT}\",\"scope\":\"${SIKA_SYSTEM_ACCOUNT}\",\"table\":\"rexpool\",\"limit\":1}' \
      | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('rows') else 1)\"
  "
  if "${CLEOS}" --url "${NODE_URL}" get table "${SIKA_SYSTEM_ACCOUNT}" "${SIKA_SYSTEM_ACCOUNT}" producers -l 5 2>/dev/null \
    | grep -q sikabpa; then
    check "6-BP schedule (sikabpa–sikabpf)" bash -c "
      \"${CLEOS}\" --url \"${NODE_URL}\" get table \"${SIKA_SYSTEM_ACCOUNT}\" \"${SIKA_SYSTEM_ACCOUNT}\" producers -l 10 2>/dev/null \
        | python3 -c \"import json,sys; names={r['owner'] for r in json.load(sys.stdin).get('rows',[])}; need={'sikabpa','sikabpb','sikabpc','sikabpd','sikabpe','sikabpf'}; sys.exit(0 if need<=names else 1)\"
    "
  fi
  if is_multinode_cluster; then
    bash "${SCRIPT_DIR}/ensure-bp-cluster-healthy.sh" || true
    check "multinode BP rotation" bash "${SCRIPT_DIR}/verify-6bp-rotation.sh"
  fi
fi
set -e

if curl -sf "${NODE_URL}/v1/chain/get_code" \
  -H 'Content-Type: application/json' \
  -d '{"account_name":"atomicassets"}' 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('wasm') else 1)" 2>/dev/null; then
  echo "  ok  atomicassets NFT contract"
else
  echo "  --  atomicassets not deployed (optional: deploy-atomicassets.sh)"
fi

set +e

if curl -sf -o /dev/null "${SIKA_APP_URL}/" 2>/dev/null; then
  echo "  ok  Sika app (${SIKA_APP_URL})"
else
  echo "  --  Sika app not on ${SIKA_APP_URL} (optional)"
fi

if curl -sf -o /dev/null "${SIKA_CHAIN_WEB_URL}/" 2>/dev/null; then
  echo "  ok  SikaChain site (${SIKA_CHAIN_WEB_URL})"
else
  echo "  --  SikaChain site not on ${SIKA_CHAIN_WEB_URL} (optional)"
fi

if curl -sf -o /dev/null "http://127.0.0.1:4000/health" 2>/dev/null; then
  echo "  ok  Wharfkit adapter (http://127.0.0.1:4000)"
else
  echo "  --  Wharfkit adapter not on :4000 (optional)"
fi

exit "${FAIL}"
