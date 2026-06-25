#!/usr/bin/env bash
# Deprivilege and clear legacy eosio.msig after sika.msig is live (dev chain only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

LEGACY_MSIG="${LEGACY_MSIG:-eosio.msig}"
MSIG_ACCOUNT="${MSIG_ACCOUNT:-sika.msig}"
SIKA_SYSTEM="${SIKA_SYSTEM_ACCOUNT:-sika}"
SIKA_RULES="${SIKA_RULES_ACCOUNT:-sika.rules}"

if [[ "${LEGACY_MSIG}" == "${MSIG_ACCOUNT}" ]]; then
  echo "SKIP: LEGACY_MSIG equals MSIG_ACCOUNT (${MSIG_ACCOUNT})"
  exit 0
fi

cleos_cmd() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

push_action_or_skip() {
  local label="$1"
  shift
  local err
  if err="$("$@" 2>&1)"; then
    return 0
  fi
  if echo "${err}" | grep -qiE 'already|duplicate|constraint|unchanged|not privileged'; then
    echo "  (skip) ${label}"
    return 0
  fi
  echo "${err}" >&2
  return 1
}

legacy_exists() {
  curl -sf "${NODE_URL}/v1/chain/get_account" \
    -H 'Content-Type: application/json' \
    -d "{\"account_name\":\"${LEGACY_MSIG}\"}" >/dev/null 2>&1
}

legacy_privileged() {
  curl -sf "${NODE_URL}/v1/chain/get_account" \
    -H 'Content-Type: application/json' \
    -d "{\"account_name\":\"${LEGACY_MSIG}\"}" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('privileged', False))"
}

msig_ready() {
  curl -sf "${NODE_URL}/v1/chain/get_account" \
    -H 'Content-Type: application/json' \
    -d "{\"account_name\":\"${MSIG_ACCOUNT}\"}" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('privileged') else 1)" 2>/dev/null
}

if ! legacy_exists; then
  echo "=== Legacy ${LEGACY_MSIG} not present — nothing to clean up ==="
  exit 0
fi

if ! msig_ready; then
  echo "FAIL: ${MSIG_ACCOUNT} is not deployed/privileged — deploy sika.msig first (deploy-msig.sh)" >&2
  exit 1
fi

PASSWORD_FILE="${ROOT}/wallet/.password"
if [[ -f "${PASSWORD_FILE}" ]]; then
  DEV_PW="$(tr -d '\n' < "${PASSWORD_FILE}")"
  cleos_cmd wallet open 2>/dev/null || true
  cleos_cmd wallet unlock --password "${DEV_PW}" 2>/dev/null || true
fi

echo "=== Cleanup legacy ${LEGACY_MSIG} (canonical msig: ${MSIG_ACCOUNT}) ==="

if [[ "$(legacy_privileged)" == "True" ]]; then
  echo "Removing privileged flag from ${LEGACY_MSIG}..."
  push_action_or_skip "${LEGACY_MSIG} setpriv off" \
    cleos_cmd push action "${SIKA_SYSTEM}" setpriv "[\"${LEGACY_MSIG}\",0]" -p "${SIKA_RULES}@active"
else
  echo "  ${LEGACY_MSIG} already non-privileged"
fi

echo "Clearing contract code on ${LEGACY_MSIG}..."
push_action_or_skip "${LEGACY_MSIG} set contract --clear" \
  cleos_cmd set contract "${LEGACY_MSIG}" . -c -p "${LEGACY_MSIG}@active"

echo "=== Legacy ${LEGACY_MSIG} retired ==="
cleos_cmd get account "${LEGACY_MSIG}" -j 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['account_name'], 'privileged', d.get('privileged'), 'code_bytes', d.get('code_hash','n/a'))" \
  || true
