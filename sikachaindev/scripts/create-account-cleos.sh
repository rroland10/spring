#!/usr/bin/env bash
# Create a dev account using cleos wallet + keosd; broadcast via bundled tx helper.
#
# cleos handles: key generation, wallet import, and all post-create actions.
# Account creation requires newaccount + buyrambytes in one transaction (Spring
# `cleos system newaccount` still queries legacy eosio.token). The bundled tx
# is built by create-account.mjs using the system key from chain.json.
#
# Usage:
#   bash scripts/create-account-cleos.sh <account> [public-key]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <account-name> [public-key]"
  exit 1
fi

ACCOUNT="$1"
PUB="${2:-}"
RAM_BYTES="${RAM_BYTES:-4096}"
KEY_FORMAT_MJS="${SCRIPT_DIR}/lib/key-format.mjs"
CREATE_MJS="${SCRIPT_DIR}/create-account.mjs"
SIKA_APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"

cleos_wallet_ready

if curl -sf "${NODE_URL}/v1/chain/get_account" \
  -H 'Content-Type: application/json' \
  -d "{\"account_name\":\"${ACCOUNT}\"}" | grep -q '"account_name"'; then
  echo "Account ${ACCOUNT} already exists"
  exit 0
fi

if [[ -z "${PUB}" ]]; then
  KEYS="$(cleos create key --to-console)"
  PVT="$(echo "${KEYS}" | awk '/Private key:/ {print $3}')"
  PUB="$(echo "${KEYS}" | awk '/Public key:/ {print $3}')"
  cleos wallet import --private-key "${PVT}"
  echo "Generated and imported key for ${ACCOUNT} (cleos wallet)"
fi

if [[ ! -f "${CREATE_MJS}" ]]; then
  echo "error: missing ${CREATE_MJS}"
  exit 1
fi
if [[ ! -d "${SIKA_APP_DIR}/node_modules/@wharfkit/antelope" ]]; then
  echo "error: WharfKit not found in ${SIKA_APP_DIR} — npm install in Sika app"
  exit 1
fi

PUB_K1="$(node "${KEY_FORMAT_MJS}" to-pub-k1 "${PUB}")"
export SIKA_APP_DIR SIKA_SYSTEM_ACCOUNT RAM_BYTES
node "${CREATE_MJS}" "${ACCOUNT}" "${PUB_K1}" "${RAM_BYTES}" "${NODE_URL}"

echo ""
echo "Created account: ${ACCOUNT}"
echo "  public key (PUB_K1): ${PUB_K1}"
echo "  key in cleos wallet — sign with: bash scripts/cleos.sh ... -p ${ACCOUNT}@active"
