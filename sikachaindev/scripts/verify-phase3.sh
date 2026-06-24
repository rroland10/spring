#!/usr/bin/env bash
# Verify Phase 3 chain: privileged system account `sika` hosts sika.system WASM.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

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

echo "=== Phase 3 verify (SIKACHAIN_DEV=${SIKACHAIN_DEV:-0}) ==="

if [[ "${SIKACHAIN_DEV:-}" != "1" ]]; then
  echo "SKIP: set SIKACHAIN_DEV=1 to run Phase 3 checks"
  exit 0
fi

EXPECTED_SYSTEM="${SIKA_SYSTEM_ACCOUNT:-sika}"

check "Spring SIKACHAIN build (sika account exists)" bash -c "
  curl -sf \"${NODE_URL}/v1/chain/get_account\" \
    -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"${EXPECTED_SYSTEM}\"}' | grep -q '\"account_name\"'
"

check "system account privileged" bash -c "
  curl -sf \"${NODE_URL}/v1/chain/get_account\" \
    -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"${EXPECTED_SYSTEM}\"}' \
    | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('privileged') else 1)\"
"

check "sika.system WASM on ${EXPECTED_SYSTEM}" bash -c "
  curl -sf \"${NODE_URL}/v1/chain/get_code\" \
    -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"${EXPECTED_SYSTEM}\"}' \
    | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('wasm') else 1)\"
"

check "producer in dev BP set" bash -c "
  head=\$(curl -sf \"${NODE_URL}/v1/chain/get_info\" \
    | python3 -c \"import json,sys; print(json.load(sys.stdin).get('head_block_producer',''))\")
  python3 - <<'PY' \"\${head}\" \"${EXPECTED_SYSTEM}\"
import sys
allowed = {sys.argv[2], 'sikabpa','sikabpb','sikabpc','sikabpd','sikabpe','sikabpf'}
sys.exit(0 if sys.argv[1] in allowed else 1)
PY
"

check "sika.msig privileged" bash -c "
  curl -sf \"${NODE_URL}/v1/chain/get_account\" \
    -H 'Content-Type: application/json' \
    -d '{\"account_name\":\"${MSIG_ACCOUNT}\"}' \
    | python3 -c \"import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('privileged') else 1)\"
"

check "SIKA token live" bash -c "
  \"${CLEOS}\" --url \"${NODE_URL}\" get currency stats sika.token SIKA 2>/dev/null \
    | python3 -c \"import json,sys; d=json.load(sys.stdin); s=d.get('SIKA',{}).get('supply','0').split()[0]; sys.exit(0 if float(s)>0 else 1)\"
"

if [[ "${FAIL}" -eq 0 ]]; then
  echo "=== Phase 3 verify complete — all checks passed ==="
else
  echo "=== Phase 3 verify failed ===" >&2
  echo "Rebuild Spring: bash scripts/build-sikachain-spring.sh" >&2
  echo "Rebuild contracts: SIKACHAIN=1 ./build.sh (sys contract dir)" >&2
  echo "Reset + bootstrap: SIKACHAIN_DEV=1 SIKA_RESET_CONFIRM=yes bash scripts/reset-chain.sh -y && bash scripts/bootstrap-dev.sh" >&2
  exit 1
fi
