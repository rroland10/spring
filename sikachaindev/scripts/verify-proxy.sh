#!/usr/bin/env bash
# Smoke-test vote proxy (regproxy + voteproducer proxy) — matches Sika app Proxy tool.
#
# Usage:
#   bash scripts/verify-proxy.sh
#   PROXY_ACCOUNT=sikauser1 VOTER_ACCOUNT=sikauser2 bash scripts/verify-proxy.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

SYS="${SIKA_SYSTEM_ACCOUNT:-sika}"
TOKEN="${SIKA_TOKEN_ACCOUNT:-sika.token}"
PROXY="${PROXY_ACCOUNT:-sikauser1}"
VOTER="${VOTER_ACCOUNT:-sikauser2}"
DEPOSIT="${PROXY_DEPOSIT:-10.0000 SIKA}"

cleos_cmd() {
  bash "${SCRIPT_DIR}/cleos.sh" "$@"
}

import_account_key() {
  local acct="$1"
  local pvt legacy
  pvt="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['accounts']['${acct}']['privateKey'])")"
  legacy="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['accounts']['${acct}']['publicKeyLegacy'])")"
  if cleos_cmd wallet keys 2>/dev/null | grep -q "${legacy}"; then
    return 0
  fi
  cleos_cmd wallet import --private-key "${pvt}" >/dev/null
  echo "  imported ${acct} key"
}

voter_field() {
  local acct="$1" field="$2"
  cleos_cmd get table "${SYS}" "${SYS}" voters -l 500 2>/dev/null | python3 -c "
import json, sys
acct, field = sys.argv[1:3]
for r in json.load(sys.stdin).get('rows', []):
    if r.get('owner') == acct:
        print(r.get(field, ''))
        break
" "${acct}" "${field}"
}

wait_voter_row() {
  local acct="$1"
  for _ in $(seq 1 20); do
    if [[ -n "$(voter_field "${acct}" owner)" ]]; then
      return 0
    fi
    sleep 0.5
  done
  echo "FAIL: voters row for ${acct} not visible" >&2
  return 1
}

is_proxy_registered() {
  [[ "$(voter_field "${PROXY}" is_proxy)" == "1" || "$(voter_field "${PROXY}" is_proxy)" == "True" ]]
}

voter_proxy() {
  voter_field "${VOTER}" proxy
}

echo "=== verify-proxy (regproxy + voteproducer proxy) ==="
echo "  proxy=${PROXY}  voter=${VOTER}  RPC=${NODE_URL}"
echo ""

cleos_wallet_ready
import_account_key "${PROXY}"
import_account_key "${VOTER}"

echo "--- 1. Register ${PROXY} as voting proxy (sika::regproxy) ---"
if is_proxy_registered; then
  echo "  SKIP: ${PROXY} already registered as proxy"
else
  cleos_cmd push action "${SYS}" regproxy "[\"${PROXY}\",true]" -p "${PROXY}@active" -x 3600
  is_proxy_registered || { echo "FAIL: ${PROXY} is_proxy not set" >&2; exit 1; }
  echo "  ok  ${PROXY} is_proxy=true"
fi

echo ""
echo "--- 2. Initialize voter ${VOTER} (delegatebw creates voters row) ---"
if [[ -z "$(voter_field "${VOTER}" owner)" ]]; then
  cleos_cmd push action "${SYS}" delegatebw \
    "[\"${VOTER}\",\"${VOTER}\",\"${DEPOSIT}\",\"${DEPOSIT}\",false]" \
    -p "${VOTER}@active" -x 3600
  wait_voter_row "${VOTER}"
  echo "  ok  delegatebw ${DEPOSIT} net+cpu"
else
  echo "  SKIP: ${VOTER} already in voters table"
fi

echo ""
echo "--- 3. Delegate vote weight to proxy ---"
cleos_cmd system voteproducer proxy "${VOTER}" "${PROXY}" -p "${VOTER}@active" -x 3600
for _ in $(seq 1 20); do
  actual="$(voter_proxy)"
  [[ "${actual}" == "${PROXY}" ]] && break
  sleep 0.5
done
if [[ "${actual}" != "${PROXY}" ]]; then
  echo "FAIL: expected ${VOTER}.proxy=${PROXY}, got '${actual}'" >&2
  exit 1
fi
echo "  ok  ${VOTER} → proxy ${PROXY}"

echo ""
echo "--- 4. Clear proxy delegation ---"
cleos_cmd system voteproducer proxy "${VOTER}" "" -p "${VOTER}@active" -x 3600
sleep 0.5
actual="$(voter_proxy)"
if [[ -n "${actual}" && "${actual}" != "null" ]]; then
  echo "FAIL: ${VOTER} still has proxy '${actual}'" >&2
  exit 1
fi
echo "  ok  ${VOTER} proxy cleared"

echo ""
echo "--- 5. Unregister proxy (optional cleanup) ---"
if [[ "${PROXY_CLEANUP:-0}" == "1" ]]; then
  cleos_cmd push action "${SYS}" regproxy "[\"${PROXY}\",false]" -p "${PROXY}@active" -x 3600
  echo "  ok  ${PROXY} unregistered"
else
  echo "  SKIP (set PROXY_CLEANUP=1 to unregister ${PROXY})"
fi

echo ""
echo "=== verify-proxy complete ==="
