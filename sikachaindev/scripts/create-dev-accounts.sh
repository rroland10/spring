#!/usr/bin/env bash
# Create and fund standard SikaChainDev developer accounts for wallet UI testing.
#
# Accounts:
#   sikadev   — primary dev wallet (WharfKit dev wallet / Anchor)
#   sikauser1 — peer wallet for send/receive tests
#   sikauser2 — second peer wallet
#
# Keys live in chain.json. Run bootstrap-dev.sh first if the chain is fresh.
#
# Usage:
#   export SIKACHAIN_DEV=1 SIKA_SYSTEM_ACCOUNT=sika
#   bash scripts/create-dev-accounts.sh
#   bash scripts/create-dev-accounts.sh sikauser1   # single account
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

BUILD_BIN="${ROOT}/../build/programs"
if [[ -x "${BUILD_BIN}/cleos/cleos" ]]; then
  CLEOS_BIN="${BUILD_BIN}/cleos/cleos"
else
  CLEOS_BIN="cleos"
fi
CLEOS_ARGS=(--url "${NODE_URL}" --wallet-url "${WALLET_URL}")

SIKA_FUND="${DEV_SIKA_FUND:-5000.0000 SIKA}"
CGHS_FUND="${DEV_CGHS_FUND:-500.0000 CGHS}"
RAM_BYTES="${RAM_BYTES:-65536}"

DEFAULT_ACCOUNTS=(sikadev sikauser1 sikauser2)
if [[ $# -gt 0 ]]; then
  ACCOUNTS=("$@")
else
  ACCOUNTS=("${DEFAULT_ACCOUNTS[@]}")
fi

account_exists() {
  curl -sf "${NODE_URL}/v1/chain/get_account" \
    -H 'Content-Type: application/json' \
    -d "{\"account_name\":\"$1\"}" | grep -q '"account_name"'
}

token_balance() {
  local acct="$1" symbol="$2"
  curl -sf "${NODE_URL}/v1/chain/get_currency_balance" \
    -H 'Content-Type: application/json' \
    -d "{\"code\":\"${SIKA_TOKEN_ACCOUNT}\",\"account\":\"${acct}\",\"symbol\":\"${symbol}\"}" \
    | python3 -c "import json,sys; b=json.load(sys.stdin); print(b[0].split()[0] if b else '0')" 2>/dev/null \
    || echo "0"
}

unlock_wallet() {
  local pw_file="${ROOT}/wallet/.password"
  if [[ -f "${pw_file}" ]]; then
    local pw
    pw="$(tr -d '\n' < "${pw_file}")"
    "${CLEOS_BIN}" "${CLEOS_ARGS[@]}" wallet unlock --password "${pw}" 2>/dev/null || true
  fi
}

fund_account() {
  local acct="$1"
  local sika_bal cghs_bal

  sika_bal="$(token_balance "${acct}" SIKA)"
  if python3 -c "import sys; sys.exit(0 if float('${sika_bal}') >= 100.0 else 1)"; then
    echo "  ${acct}: ${sika_bal} SIKA (ok)"
  else
    echo "  funding ${acct} with ${SIKA_FUND}..."
    unlock_wallet
    "${CLEOS_BIN}" "${CLEOS_ARGS[@]}" transfer "${SIKA_SYSTEM_ACCOUNT}" "${acct}" "${SIKA_FUND}" \
      "SikaChainDev dev fund" -c "${SIKA_TOKEN_ACCOUNT}"
  fi

  cghs_bal="$(token_balance "${acct}" CGHS)"
  if python3 -c "import sys; sys.exit(0 if float('${cghs_bal}') >= 1.0 else 1)"; then
    echo "  ${acct}: ${cghs_bal} CGHS (ok)"
  else
    echo "  issuing ${CGHS_FUND} CGHS to ${acct}..."
    unlock_wallet
    "${CLEOS_BIN}" "${CLEOS_ARGS[@]}" push action "${SIKA_TOKEN_ACCOUNT}" issue \
      "[\"${acct}\",\"${CGHS_FUND}\",\"SikaChainDev dev fund\"]" -p sika.issue@active
  fi
}

echo "=== SikaChainDev developer accounts ==="
echo "  system=${SIKA_SYSTEM_ACCOUNT}  RPC=${NODE_URL}"
echo ""

bash "${SCRIPT_DIR}/wait-for-rpc.sh" 120
bash "${SCRIPT_DIR}/setup-wallet.sh"

for acct in "${ACCOUNTS[@]}"; do
  pub="$(python3 -c "
import json, sys
c = json.load(open('${ROOT}/chain.json'))
a = c.get('accounts', {}).get('${acct}')
print(a.get('publicKey','') if a else '')
" 2>/dev/null || true)"

  if [[ -z "${pub}" ]]; then
    echo "WARN: no publicKey for ${acct} in chain.json — skipping"
    continue
  fi

  echo "--- ${acct} ---"
  if account_exists "${acct}"; then
    echo "  account exists"
  else
    echo "  creating ${acct}..."
    RAM_BYTES="${RAM_BYTES}" bash "${SCRIPT_DIR}/create-account.sh" "${acct}" "${pub}"
  fi
  fund_account "${acct}"
  echo ""
done

bash "${SCRIPT_DIR}/sync-app-env.mjs" --local 2>/dev/null || bash "${SCRIPT_DIR}/sync-dev-env.sh" 2>/dev/null || true

echo "=== Dev accounts ready ==="
bash "${SCRIPT_DIR}/status.sh"
