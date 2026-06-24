#!/usr/bin/env bash
# Feature test matrix for SikaChainDev Phase 3 — chain, settlement, wallet UI, Hyperion, apps.
#
# Usage:
#   export SIKACHAIN_DEV=1 SIKA_SYSTEM_ACCOUNT=sika
#   bash scripts/test-features.sh              # read-only + UI probes
#   ON_CHAIN=1 bash scripts/test-features.sh   # include verify-dev (settlement/msig/NFT txs)
#   WALLET_UI=1 bash scripts/test-features.sh  # Playwright wallet UI (+ MSIG + import when on-chain)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

SYS="${SIKA_SYSTEM_ACCOUNT:-sika}"
TOKEN="${SIKA_TOKEN_ACCOUNT:-sika.token}"
DEV="${1:-sikadev}"
FAIL=0
APP_URL="${SIKA_APP_URL:-http://127.0.0.1:3003}"
WEB_URL="${SIKA_CHAIN_WEB_URL:-http://127.0.0.1:3004}"
HYPERION="$(python3 -c "import json; print(json.load(open('${SCRIPT_DIR}/../chain.json')).get('hyperionUrl','') or '')" 2>/dev/null)"

run() {
  local label="$1"
  shift
  printf "  %-42s " "${label}"
  if "$@" >/dev/null 2>&1; then
    echo "ok"
  else
    echo "FAIL"
    FAIL=1
  fi
}

rpc_table() {
  local code="$1" scope="$2" table="$3"
  curl -sf "${NODE_URL}/v1/chain/get_table_rows" \
    -H 'Content-Type: application/json' \
    -d "{\"json\":true,\"code\":\"${code}\",\"scope\":\"${scope}\",\"table\":\"${table}\",\"limit\":1}" \
    | python3 -c "import json,sys; json.load(sys.stdin)"
}

curl_page() {
  local url="$1"
  local attempt code
  for attempt in 1 2 3; do
    code=$(curl -sfL -m 60 -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || echo "000")
    if echo "${code}" | grep -qE '^(200|307)$'; then
      return 0
    fi
    sleep 2
  done
  return 1
}

warm_app_pages() {
  curl -sfL -m 90 -o /dev/null "${APP_URL}/app/home" >/dev/null 2>&1 || true
  sleep 1
}

echo "=== SikaChainDev feature tests ==="
echo "  system=${SYS}  dev=${DEV}  RPC=${NODE_URL}"
echo ""

bash "${SCRIPT_DIR}/wait-for-rpc.sh" 60

DEV_CHAIN_ID="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json')).get('chainId',''))" 2>/dev/null || true)"
LIVE_CHAIN_ID="$(curl -sf "${NODE_URL}/v1/chain/get_info" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("chain_id",""))' 2>/dev/null || true)"
TESTNET_MODE=0
TESTNET_HYPERION="${TESTNET_HYPERION_URL:-http://127.0.0.1:7002}"
if [[ -n "${DEV_CHAIN_ID}" && -n "${LIVE_CHAIN_ID}" && "${DEV_CHAIN_ID}" != "${LIVE_CHAIN_ID}" ]]; then
  TESTNET_MODE=1
  if curl -sf "${TESTNET_HYPERION}/v2/health" >/dev/null 2>&1; then
    HYPERION="${TESTNET_HYPERION}"
    echo "  note: docker testnet — Hyperion ${HYPERION} (skip slow /explore/chain SSR)"
  else
    HYPERION=""
    echo "  note: docker testnet — no Hyperion at ${TESTNET_HYPERION} (run setup-hyperion-testnet-local.sh)"
  fi
fi
echo ""

echo "--- Chain & tokens ---"
run "nodeos RPC" curl -sf "${NODE_URL}/v1/chain/get_info"
run "nodeos RPC CORS" bash -c "
  curl -sfI -X OPTIONS '${NODE_URL}/v1/chain/get_info' \
    -H 'Origin: http://127.0.0.1:3003' \
    -H 'Access-Control-Request-Method: POST' \
    | grep -qi 'access-control-allow-origin'
"
run "producer in 6-BP set" bash -c "
  head=\$(curl -sf '${NODE_URL}/v1/chain/get_info' \
    | python3 -c \"import json,sys; print(json.load(sys.stdin).get('head_block_producer',''))\")
  python3 - <<'PY' \"\${head}\" \"${SYS}\"
import sys
allowed = {sys.argv[2], 'sikabpa','sikabpb','sikabpc','sikabpd','sikabpe','sikabpf'}
sys.exit(0 if sys.argv[1] in allowed else 1)
PY
"
run "${SYS} privileged" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_account' -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"${SYS}\"}' \
    | python3 -c \"import json,sys; a=json.load(sys.stdin); sys.exit(0 if a.get('privileged') else 1)\"
"
run "SIKA token supply" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_currency_stats' -H 'Content-Type: application/json' \
    -d '{\"code\":\"${TOKEN}\",\"symbol\":\"SIKA\"}' \
    | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'SIKA' in d else 1)\"
"
run "CGHS stablecoin" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_currency_stats' -H 'Content-Type: application/json' \
    -d '{\"code\":\"${TOKEN}\",\"symbol\":\"CGHS\"}' \
    | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'CGHS' in d else 1)\"
"
run "${DEV} SIKA balance" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_currency_balance' -H 'Content-Type: application/json' \
    -d '{\"code\":\"${TOKEN}\",\"account\":\"${DEV}\",\"symbol\":\"SIKA\"}' \
    | python3 -c \"import json,sys; b=json.load(sys.stdin); sys.exit(0 if b and float(b[0].split()[0])>0 else 1)\"
"

echo ""
echo "--- Dev accounts (chain.json) ---"
run "smoke all dev accounts" bash "${SCRIPT_DIR}/smoke-dev-accounts.sh"
run "peer transfer sikadev→sikauser1 (SIKA)" bash "${SCRIPT_DIR}/verify-peer-transfer.sh"
run "peer transfer sikadev→sikauser2 (CGHS)" bash -c "PEER_TO=sikauser2 PEER_SYMBOL=CGHS bash '${SCRIPT_DIR}/verify-peer-transfer.sh'"

echo ""
echo "--- System contract (${SYS}) ---"
run "rammarket table" rpc_table "${SYS}" "${SYS}" "rammarket"
run "rexpool table" rpc_table "${SYS}" "${SYS}" "rexpool"
run "delband ABI/query" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_table_rows' -H 'Content-Type: application/json' \
    -d '{\"json\":true,\"code\":\"${SYS}\",\"scope\":\"${DEV}\",\"table\":\"delband\",\"limit\":5}' \
    | python3 -c \"import json,sys; json.load(sys.stdin)\"
"
run "rexbal table" rpc_table "${SYS}" "${SYS}" "rexbal"
run "voters table" rpc_table "${SYS}" "${SYS}" "voters"
run "producers table" rpc_table "${SYS}" "${SYS}" "producers"

echo ""
echo "--- Settlement (sika.treas) ---"
run "treas reserve singleton" rpc_table "sika.treas" "sika.treas" "reserve"
run "fxquotes oracle" rpc_table "sika.treas" "sika.treas" "fxquotes"
run "marketpref table" rpc_table "sika.treas" "sika.treas" "marketpref"

echo ""
echo "--- Governance & NFTs ---"
run "sika.msig privileged" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_account' -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"sika.msig\"}' \
    | python3 -c \"import json,sys; a=json.load(sys.stdin); sys.exit(0 if a.get('privileged') else 1)\"
"
run "msig proposals table" rpc_table "sika.msig" "sika.msig" "proposal"
run "atomicassets deployed" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_code' -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"atomicassets\"}' \
    | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('wasm') else 1)\"
"
run "${DEV} NFT assets" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_table_rows' -H 'Content-Type: application/json' \
    -d '{\"json\":true,\"code\":\"atomicassets\",\"scope\":\"${DEV}\",\"table\":\"assets\",\"limit\":1}' \
    | python3 -c \"import json,sys; r=json.load(sys.stdin); sys.exit(0 if r.get('rows') is not None else 1)\"
"

if [[ -n "${HYPERION}" ]]; then
  echo ""
  echo "--- Hyperion (${HYPERION}) ---"
  run "Hyperion /v2/health" curl -sf "${HYPERION}/v2/health"
  run "get_actions (${SYS})" bash -c "
    curl -sf '${HYPERION}/v2/history/get_actions?account=${SYS}&limit=1' \
      | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'actions' in d else 1)\"
  "
  run "get_actions (${DEV})" bash -c "
    curl -sf '${HYPERION}/v2/history/get_actions?account=${DEV}&limit=5' \
      | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'actions' in d else 1)\"
  "
else
  echo ""
  echo "--- Hyperion ---"
  if [[ "${TESTNET_MODE}" == "1" ]]; then
    echo "  --  not running (bash scripts/setup-hyperion-testnet-local.sh)"
  else
    echo "  --  not configured in chain.json"
  fi
fi

echo ""
echo "--- Sika app pages (${APP_URL}) ---"
warm_app_pages
APP_PATHS=(
  "/" "/app/home" "/app/vote" "/app/earn" "/app/business" "/app/explore" "/app/explore/search"
  "/app/send" "/app/activity" "/app/notifications" "/app/tools" "/app/tools/ram" "/app/tools/rent"
  "/app/tools/allocate" "/app/tools/proxy" "/app/explore/topholders" "/app/explore/rex"
  "/app/explore/account/sikauser1"
)
if [[ "${TESTNET_MODE}" != "1" ]]; then
  APP_PATHS+=("/app/explore/chain")
else
  echo "  GET /app/explore/chain                 -- (skip: slow SSR on docker testnet RPC)"
fi
for path in "${APP_PATHS[@]}"; do
  run "GET ${path}" curl_page "${APP_URL}${path}"
done
run "GET /account (legacy)" curl_page "${APP_URL}/account"
run "GET /account/info/sikadev" curl_page "${APP_URL}/account/info/sikadev"

if [[ -n "${HYPERION}" ]]; then
  run "Hyperion proxy API" bash -c "
    curl -sfL -m 15 '${APP_URL}/api/hyperion/v2/history/get_actions?account=${DEV}&limit=1' \
      | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('actions') is not None else 1)\"
  "
elif [[ "${TESTNET_MODE}" == "1" ]]; then
  echo "  Hyperion proxy API                       -- (skip: run setup-hyperion-testnet-local.sh + sync-testnet-app-env)"
fi

echo ""
echo "--- SikaChain site (${WEB_URL}) ---"
GTM_LOCALE="${GTM_LOCALE:-en}"
for path in "/" "/producers" "/explorer" "/${GTM_LOCALE}/explorer"; do
  run "GET ${path}" curl_page "${WEB_URL}${path}" || true
done
run "GTM account page (sikadev)" curl_page "${WEB_URL}/${GTM_LOCALE}/explorer/account/sikadev" || true

echo ""
echo "--- Wharfkit adapter (:4000) ---"
run "GET /health" curl -sf "http://127.0.0.1:4000/health"
# /diag expects Postgres — optional
if curl -sf "http://127.0.0.1:4000/diag" 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('ok') else 1)" 2>/dev/null; then
  echo "  GET /diag (full readiness)                 ok"
else
  echo "  GET /diag (full readiness)                 -- (Postgres optional for dev)"
fi

if [[ "${ON_CHAIN:-0}" == "1" ]]; then
  echo ""
  echo "--- On-chain feature txs (verify-dev) ---"
  if VERIFY_ATOMICASSETS=1 bash "${SCRIPT_DIR}/verify-dev.sh"; then
    echo "  verify-dev                                 ok"
  else
    echo "  verify-dev                                 FAIL"
    FAIL=1
  fi
else
  echo ""
  echo "--- On-chain txs ---"
  echo "  SKIP (set ON_CHAIN=1 to run settlement/msig/NFT txs)"
fi

if [[ "${WALLET_UI:-0}" == "1" ]]; then
  echo ""
  echo "--- Wallet UI (Playwright + dev wallet) ---"
  WALLET_UI_ON_CHAIN_SEND=0
  if [[ "${ON_CHAIN:-0}" == "1" || "${VERIFY_DEV_ON_CHAIN_SEND:-0}" == "1" ]]; then
    WALLET_UI_ON_CHAIN_SEND=1
  fi
  WALLET_MSIG_RUN="${WALLET_MSIG:-${WALLET_UI_ON_CHAIN_SEND}}"
  if [[ "${WALLET_MSIG_RUN}" == "1" ]]; then
    if ON_CHAIN_SEND="${WALLET_UI_ON_CHAIN_SEND}" GH_V1=0 PLAYWRIGHT_REUSE_SERVER=1 \
      bash "${SCRIPT_DIR}/test-wallet-live.sh"; then
      echo "  test-wallet-live.sh                        ok"
    else
      echo "  test-wallet-live.sh                        FAIL"
      FAIL=1
    fi
  elif ON_CHAIN_SEND="${WALLET_UI_ON_CHAIN_SEND}" PLAYWRIGHT_REUSE_SERVER=1 \
    bash "${SCRIPT_DIR}/test-wallet-ui.sh"; then
    echo "  test-wallet-ui.sh                          ok"
  else
    echo "  test-wallet-ui.sh                          FAIL"
    FAIL=1
  fi
  warm_app_pages
else
  echo ""
  echo "--- Wallet UI ---"
  echo "  SKIP (set WALLET_UI=1 to run Playwright live-chain tests)"
fi

echo ""
if [[ "${FAIL}" -eq 0 ]]; then
  echo "=== feature tests complete — all checks passed ==="
else
  echo "=== feature tests complete — one or more checks failed ===" >&2
  exit 1
fi
