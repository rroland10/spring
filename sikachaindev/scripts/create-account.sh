#!/usr/bin/env bash
# Create a dev account on SikaChainDev (sika.system @ privileged system account).
set -euo pipefail
source "$(dirname "$0")/env.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <account-name> [public-key]"
  echo "  Creates account authorized by ${SIKA_SYSTEM_ACCOUNT}. Generates a key if public-key omitted."
  exit 1
fi

ACCOUNT="$1"
PUB="${2:-}"
RAM_BYTES="${RAM_BYTES:-4096}"
SIKA_APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
CREATE_MJS="$(cd "$(dirname "$0")" && pwd)/create-account.mjs"
KEY_FORMAT_MJS="$(cd "$(dirname "$0")" && pwd)/lib/key-format.mjs"

PASSWORD_FILE="${ROOT}/wallet/.password"
if [[ -f "${PASSWORD_FILE}" ]]; then
  DEV_PW="$(tr -d '\n' < "${PASSWORD_FILE}")"
  cleos wallet open 2>/dev/null || true
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet unlock --password "${DEV_PW}" 2>/dev/null || true
fi

if [[ -z "${PUB}" ]]; then
  KEYS=$("${CLEOS}" create key --to-console)
  PVT=$(echo "${KEYS}" | awk '/Private key:/ {print $3}')
  PUB=$(echo "${KEYS}" | awk '/Public key:/ {print $3}')
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet import --private-key "${PVT}"
  echo "Generated and imported key for ${ACCOUNT}"
fi

if [[ ! -d "${SIKA_APP_DIR}/node_modules/@wharfkit/antelope" ]]; then
  echo "error: WharfKit not found in ${SIKA_APP_DIR} — run npm install in Sika app"
  exit 1
fi

export SIKA_APP_DIR
export SIKA_SYSTEM_ACCOUNT
PUB_K1="$(node "${KEY_FORMAT_MJS}" to-pub-k1 "${PUB}")"
node "${CREATE_MJS}" "${ACCOUNT}" "${PUB_K1}" "${RAM_BYTES}" "${NODE_URL}"

echo ""
echo "Created account: ${ACCOUNT}"
echo "  public key (PUB_K1): ${PUB_K1}"
if [[ "${PUB}" != "${PUB_K1}" ]]; then
  echo "  public key (legacy): ${PUB}"
fi
echo "  RAM bytes: ${RAM_BYTES}"
