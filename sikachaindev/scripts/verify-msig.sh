#!/usr/bin/env bash
# Smoke-test sika.msig propose → approve → exec on SikaChainDev.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

MSIG_ACCOUNT="${MSIG_ACCOUNT:-sika.msig}"
TOKEN="${SIKA_TOKEN_ACCOUNT:-sika.token}"
PROPOSER="${MSIG_TEST_PROPOSER:-${SIKA_SYSTEM_ACCOUNT}}"
AMOUNT="${MSIG_TEST_AMOUNT:-1.0000 SIKA}"
RECIPIENT="${MSIG_TEST_RECIPIENT:-sika.guard}"

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

proposal_name() {
  msig_proposal_name prop
}

unlock_wallet

if ! curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${MSIG_ACCOUNT}\"}" >/dev/null 2>&1; then
  echo "FAIL: ${MSIG_ACCOUNT} not deployed — run deploy-msig.sh" >&2
  exit 1
fi

PRIV=$(curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${MSIG_ACCOUNT}\"}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('privileged', False))")
if [[ "${PRIV}" != "True" ]]; then
  echo "FAIL: ${MSIG_ACCOUNT} is not privileged — run deploy-msig.sh (setpriv via sika.rules)" >&2
  exit 1
fi
echo "OK: ${MSIG_ACCOUNT} privileged"

PROP="$(proposal_name)"
echo "=== 1. propose ${PROP} (${AMOUNT} transfer) ==="
export MSIG_ACCOUNT MSIG_ABI_PATH="${ROOT}/.msig-build/${MSIG_ACCOUNT}/${MSIG_ACCOUNT}.abi"
node "${SCRIPT_DIR}/msig-propose-transfer.mjs" "${PROPOSER}" "${PROP}" "${RECIPIENT}" "${AMOUNT}" "verify-msig" "${NODE_URL}"

msig_wait_proposal "${PROPOSER}" "${PROP}"

echo "=== 2. approve ${PROP} ==="
cleos_cmd push action "${MSIG_ACCOUNT}" approve \
  "[\"${PROPOSER}\",\"${PROP}\",{\"actor\":\"${PROPOSER}\",\"permission\":\"active\"}]" \
  -p "${PROPOSER}@active"

msig_wait_approval "${PROPOSER}" "${PROP}"

echo "=== 3. verify proposal row ==="
ROWS=$(curl -sf "${NODE_URL}/v1/chain/get_table_rows" \
  -d "{\"json\":true,\"code\":\"${MSIG_ACCOUNT}\",\"scope\":\"${PROPOSER}\",\"table\":\"proposal\",\"lower_bound\":\"${PROP}\",\"upper_bound\":\"${PROP}\",\"limit\":1}" \
  | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('rows',[])))")
if [[ "${ROWS}" != "1" ]]; then
  echo "FAIL: proposal ${PROP} not found in table" >&2
  exit 1
fi
echo "OK: proposal ${PROP} stored"

APPROVALS=$(curl -sf "${NODE_URL}/v1/chain/get_table_rows" \
  -d "{\"json\":true,\"code\":\"${MSIG_ACCOUNT}\",\"scope\":\"${PROPOSER}\",\"table\":\"approvals2\",\"lower_bound\":\"${PROP}\",\"upper_bound\":\"${PROP}\",\"limit\":1}" \
  | python3 -c "
import json, sys
rows = json.load(sys.stdin).get('rows', [])
print(len(rows[0].get('provided_approvals', [])) if rows else 0)
")
if [[ "${APPROVALS}" -lt 1 ]]; then
  echo "FAIL: no approvals recorded for ${PROP}" >&2
  exit 1
fi
echo "OK: ${APPROVALS} approval(s) on record"

echo "=== 4. exec ${PROP} ==="
cleos_cmd push action "${MSIG_ACCOUNT}" exec "[\"${PROPOSER}\",\"${PROP}\",\"${PROPOSER}\"]" -p "${PROPOSER}@active"

for _ in $(seq 1 60); do
  REMAINING=$(curl -sf "${NODE_URL}/v1/chain/get_table_rows" \
    -d "{\"json\":true,\"code\":\"${MSIG_ACCOUNT}\",\"scope\":\"${PROPOSER}\",\"table\":\"proposal\",\"lower_bound\":\"${PROP}\",\"upper_bound\":\"${PROP}\",\"limit\":1}" \
    | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('rows',[])))")
  if [[ "${REMAINING}" == "0" ]]; then
    break
  fi
  sleep 0.5
done
if [[ "${REMAINING}" != "0" ]]; then
  echo "FAIL: proposal ${PROP} still in table after exec" >&2
  exit 1
fi
echo "OK: proposal executed and cleared"

echo "=== verify-msig complete ==="
