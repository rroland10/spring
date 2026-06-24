#!/usr/bin/env bash
# Cancel open msig proposals for dev accounts (clears stale E2E / smoke proposals).
#
# Usage:
#   bash scripts/cleanup-msig-proposals.sh
#   MSIG_CLEANUP_PROPOSERS=sikadev,sika bash scripts/cleanup-msig-proposals.sh
#   MSIG_CLEANUP_DRY_RUN=1 bash scripts/cleanup-msig-proposals.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

MSIG_ACCOUNT="${MSIG_ACCOUNT:-sika.msig}"
PROPOSERS="${MSIG_CLEANUP_PROPOSERS:-sikadev}"
DRY_RUN="${MSIG_CLEANUP_DRY_RUN:-0}"

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

import_proposer_key() {
  local proposer="$1"
  if ! python3 -c "import json; json.load(open('${ROOT}/chain.json'))['accounts']['${proposer}']" 2>/dev/null; then
    echo "  skip ${proposer}: no key in chain.json" >&2
    return 1
  fi
  local pvt legacy
  pvt="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['accounts']['${proposer}']['privateKey'])")"
  legacy="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['accounts']['${proposer}']['publicKeyLegacy'])")"
  if cleos_cmd wallet keys 2>/dev/null | grep -q "${legacy}"; then
    return 0
  fi
  cleos_cmd wallet import --private-key "${pvt}" >/dev/null
  echo "  imported ${proposer} key into dev wallet"
}

list_open_proposals() {
  local proposer="$1"
  curl -sf "${NODE_URL}/v1/chain/get_table_rows" \
    -H 'Content-Type: application/json' \
    -d "{\"json\":true,\"code\":\"${MSIG_ACCOUNT}\",\"scope\":\"${proposer}\",\"table\":\"proposal\",\"limit\":500}" \
    | python3 -c "
import json, sys
rows = json.load(sys.stdin).get('rows', [])
for r in rows:
    name = r.get('proposal_name')
    if name:
        print(name)
"
}

cancel_proposal() {
  local proposer="$1" prop="$2"
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "  [dry-run] cancel ${prop} @ ${proposer}"
    return 0
  fi
  if cleos_cmd push action "${MSIG_ACCOUNT}" cancel \
    "[\"${proposer}\",\"${prop}\",\"${proposer}\"]" \
    -p "${proposer}@active" \
    --return-failure-trace false --use-old-rpc 2>/dev/null; then
    echo "  canceled ${prop}"
    return 0
  fi
  echo "  warn: could not cancel ${prop} (may already be gone)" >&2
  return 0
}

if ! curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${MSIG_ACCOUNT}\"}" >/dev/null 2>&1; then
  echo "SKIP: ${MSIG_ACCOUNT} not deployed" >&2
  exit 0
fi

bash "${SCRIPT_DIR}/wait-for-rpc.sh" 30

unlock_wallet

echo "=== Cleanup open ${MSIG_ACCOUNT} proposals ==="
total=0
IFS=',' read -r -a proposer_list <<< "${PROPOSERS}"
for proposer in "${proposer_list[@]}"; do
  proposer="$(echo "${proposer}" | tr -d ' ')"
  [[ -n "${proposer}" ]] || continue
  if ! curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${proposer}\"}" >/dev/null 2>&1; then
    echo "  skip ${proposer}: account missing"
    continue
  fi
  import_proposer_key "${proposer}" || continue
  props="$(list_open_proposals "${proposer}")"
  if [[ -z "${props}" ]]; then
    echo "  ${proposer}: no open proposals"
    continue
  fi
  prop_count="$(printf '%s\n' "${props}" | sed '/^$/d' | wc -l | tr -d ' ')"
  echo "  ${proposer}: ${prop_count} open proposal(s)"
  while IFS= read -r prop; do
    [[ -n "${prop}" ]] || continue
    cancel_proposal "${proposer}" "${prop}"
    total=$((total + 1))
  done <<< "${props}"
done

echo "=== cleanup-msig-proposals complete (${total} canceled) ==="
