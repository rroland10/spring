#!/usr/bin/env bash
# Smoke-test msig on a user account (business wallet pattern) using sikadev key.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

MSIG_ACCOUNT="${MSIG_ACCOUNT:-sika.msig}"
TOKEN="${SIKA_TOKEN_ACCOUNT:-sika.token}"
PROPOSER="${MSIG_BIZ_TEST_PROPOSER:-sikadev}"
AMOUNT="${MSIG_TEST_AMOUNT:-0.5000 SIKA}"
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
  msig_proposal_name biz
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

unlock_wallet
import_sikadev_key

if ! curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${MSIG_ACCOUNT}\"}" >/dev/null 2>&1; then
  echo "FAIL: ${MSIG_ACCOUNT} not deployed" >&2
  exit 1
fi

PRIV=$(curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${MSIG_ACCOUNT}\"}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('privileged', False))")
if [[ "${PRIV}" != "True" ]]; then
  echo "FAIL: ${MSIG_ACCOUNT} not privileged" >&2
  exit 1
fi

if ! curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${PROPOSER}\"}" >/dev/null 2>&1; then
  echo "FAIL: proposer ${PROPOSER} missing — run bootstrap-dev.sh" >&2
  exit 1
fi

SIKA_SYSTEM="${SIKA_SYSTEM_ACCOUNT:-sika}"
ram_quota=$("${CLEOS}" --url "${NODE_URL}" get account "${PROPOSER}" -j 2>/dev/null \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('ram_quota',0))" 2>/dev/null || echo "0")
if [[ "${ram_quota}" -lt 32768 ]]; then
  need=$(( 65536 - ram_quota + 4096 ))
  echo "Ensuring ${PROPOSER} RAM (quota ${ram_quota} → +${need} bytes)..."
  cleos_cmd push action "${SIKA_SYSTEM}" buyrambytes \
    "[\"sika.guard\",\"${PROPOSER}\",${need}]" -p sika.guard@active \
    --return-failure-trace false --use-old-rpc
fi

PROP="$(proposal_name)"
echo "=== 1. propose ${PROP} from ${PROPOSER} ==="
export MSIG_ACCOUNT MSIG_ABI_PATH="${ROOT}/.msig-build/${MSIG_ACCOUNT}/${MSIG_ACCOUNT}.abi"
node "${SCRIPT_DIR}/msig-propose-transfer.mjs" "${PROPOSER}" "${PROP}" "${RECIPIENT}" "${AMOUNT}" "verify-msig-business" "${NODE_URL}"

msig_wait_proposal "${PROPOSER}" "${PROP}"

echo "=== 2. approve ==="
cleos_cmd push action "${MSIG_ACCOUNT}" approve \
  "[\"${PROPOSER}\",\"${PROP}\",{\"actor\":\"${PROPOSER}\",\"permission\":\"active\"}]" \
  -p "${PROPOSER}@active"

msig_wait_approval "${PROPOSER}" "${PROP}"

echo "=== 3. exec ==="
for attempt in 1 2 3; do
  if cleos_cmd push action "${MSIG_ACCOUNT}" exec "[\"${PROPOSER}\",\"${PROP}\",\"${PROPOSER}\"]" -p "${PROPOSER}@active"; then
    break
  fi
  if [[ "${attempt}" -eq 3 ]]; then
    echo "FAIL: msig exec failed after ${attempt} attempts" >&2
    exit 1
  fi
  echo "  exec attempt ${attempt} failed — retrying after approval sync..."
  msig_wait_approval "${PROPOSER}" "${PROP}" 30
  sleep 1
done

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
  echo "FAIL: proposal still in table after exec" >&2
  exit 1
fi

echo "=== verify-msig-business complete ==="
