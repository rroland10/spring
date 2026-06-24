#!/usr/bin/env bash
# Create sikamsig1 — dev account with 2-of-3 linked active permission for business import E2E.
#
# Active authority: sikadev + sikauser1 + sikauser2 (threshold 2).
# Owner: sikadev key (from chain.json) so updates remain scriptable.
#
# Usage:
#   bash scripts/setup-biz-msig-dev.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

ACCOUNT="${BIZ_MSIG_DEV_ACCOUNT:-sikamsig1}"
MEMBER_A="${BIZ_MSIG_MEMBER_A:-sikadev}"
MEMBER_B="${BIZ_MSIG_MEMBER_B:-sikauser1}"
MEMBER_C="${BIZ_MSIG_MEMBER_C:-sikauser2}"
THRESHOLD="${BIZ_MSIG_THRESHOLD:-2}"
RAM_BYTES="${RAM_BYTES:-65536}"

cleos_cmd() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

unlock_wallet() {
  cleos_cmd wallet open 2>/dev/null || true
  if [[ -f "${ROOT}/wallet/.password" ]]; then
    local pw
    pw="$(tr -d '\n' < "${ROOT}/wallet/.password")"
    cleos_cmd wallet unlock --password "${pw}" 2>/dev/null || true
  fi
}

import_sikadev_key() {
  local pvt legacy
  pvt="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['accounts']['sikadev']['privateKey'])")"
  legacy="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['accounts']['sikadev']['publicKeyLegacy'])")"
  if cleos_cmd wallet keys 2>/dev/null | grep -q "${legacy}"; then
    return 0
  fi
  cleos_cmd wallet import --private-key "${pvt}" >/dev/null
  echo "  imported sikadev key into dev wallet"
}

account_exists() {
  curl -sf "${NODE_URL}/v1/chain/get_account" \
    -d "{\"account_name\":\"${ACCOUNT}\"}" >/dev/null 2>&1
}

active_is_multisig() {
  curl -sf "${NODE_URL}/v1/chain/get_account" \
    -d "{\"account_name\":\"${ACCOUNT}\"}" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data.get('permissions', []):
    if p.get('perm_name') != 'active':
        continue
    auth = p.get('required_auth', {})
    accounts = auth.get('accounts', [])
    if auth.get('threshold', 1) >= ${THRESHOLD} and len(accounts) >= 3:
        sys.exit(0)
sys.exit(1)
" 2>/dev/null
}

echo "=== Setup business multisig dev account (${ACCOUNT}) ==="
bash "${SCRIPT_DIR}/wait-for-rpc.sh" 60

for peer in "${MEMBER_A}" "${MEMBER_B}" "${MEMBER_C}"; do
  if ! curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${peer}\"}" >/dev/null 2>&1; then
    echo "FAIL: member ${peer} missing — run: bash scripts/create-dev-accounts.sh" >&2
    exit 1
  fi
done

unlock_wallet
import_sikadev_key

OWNER_PUB="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['accounts']['sikadev']['publicKey'])")"

if ! account_exists; then
  echo "  creating ${ACCOUNT}..."
  RAM_BYTES="${RAM_BYTES}" bash "${SCRIPT_DIR}/create-account.sh" "${ACCOUNT}" "${OWNER_PUB}"
else
  echo "  ${ACCOUNT} exists"
fi

if active_is_multisig; then
  echo "  active permission already 2-of-3 linked — ok"
else
  echo "  updating active → ${THRESHOLD}-of-3 (${MEMBER_A}, ${MEMBER_B}, ${MEMBER_C})..."
  cleos_cmd push action "${SIKA_SYSTEM_ACCOUNT}" updateauth \
    "[\"${ACCOUNT}\",\"active\",\"owner\",{\"threshold\":${THRESHOLD},\"accounts\":[{\"permission\":{\"actor\":\"${MEMBER_A}\",\"permission\":\"active\"},\"weight\":1},{\"permission\":{\"actor\":\"${MEMBER_B}\",\"permission\":\"active\"},\"weight\":1},{\"permission\":{\"actor\":\"${MEMBER_C}\",\"permission\":\"active\"},\"weight\":1}],\"keys\":[],\"waits\":[]}]" \
    -p "${ACCOUNT}@owner" \
    --return-failure-trace false --use-old-rpc
fi

echo "  funding ${ACCOUNT} (minimal)..."
unlock_wallet
cleos_cmd transfer "${SIKA_SYSTEM_ACCOUNT}" "${ACCOUNT}" "500.0000 SIKA" \
  "biz msig dev fund" -c "${SIKA_TOKEN_ACCOUNT}" 2>/dev/null \
  || echo "  (skip SIKA fund — may already be funded)"
cleos_cmd push action "${SIKA_TOKEN_ACCOUNT}" issue \
  "[\"${ACCOUNT}\",\"50.0000 CGHS\",\"biz msig dev fund\"]" \
  -p sika.issue@active 2>/dev/null \
  || echo "  (skip CGHS issue — may already be funded)"

echo "=== setup-biz-msig-dev complete ==="
