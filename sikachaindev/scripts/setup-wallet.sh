#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_BIN="${ROOT}/../build/programs"
if [[ -z "${CLEOS:-}" ]]; then
  if [[ -x "${BUILD_BIN}/cleos/cleos" ]]; then
    CLEOS="${BUILD_BIN}/cleos/cleos"
  else
    CLEOS="cleos"
  fi
fi
WALLET_URL="${WALLET_URL:-http://127.0.0.1:8899}"
NODE_URL="${NODE_URL:-http://127.0.0.1:8888}"
DEV_PRIVATE_KEY="5KQwrPbwdL6PhXujxW37FSSQZ1JiwsST4cqQzDeyXtP79zkvFD3"
PASSWORD_FILE="${ROOT}/wallet/.password"

if ! command -v "${CLEOS}" >/dev/null 2>&1; then
  echo "error: cleos not found. Install Spring or set CLEOS=/path/to/cleos"
  exit 1
fi

CLEOS_ARGS=(--url "${NODE_URL}" --wallet-url "${WALLET_URL}")

if ! curl -sf "${WALLET_URL}/v1/wallet/list_wallets" >/dev/null 2>&1; then
  echo "error: keosd not reachable at ${WALLET_URL} — run start-keosd.sh first"
  exit 1
fi

mkdir -p "${ROOT}/wallet"

echo "Creating default wallet and importing SikaChainDev dev key..."
if [[ ! -f "${ROOT}/wallet/default.wallet" ]]; then
  "${CLEOS}" "${CLEOS_ARGS[@]}" wallet create --file "${PASSWORD_FILE}"
else
  "${CLEOS}" "${CLEOS_ARGS[@]}" wallet open || true
fi

WALLET_PASSWORD="$(tr -d '\n' < "${PASSWORD_FILE}")"
"${CLEOS}" "${CLEOS_ARGS[@]}" wallet unlock --password "${WALLET_PASSWORD}" 2>/dev/null || true
if ! "${CLEOS}" "${CLEOS_ARGS[@]}" wallet keys | grep -Eq "EOS6MRyAjQq8ud7hVNYcfnVPJqcVpscN5So8BhtHuGYqET5GDW5CV|PUB_K1_6MRyAjQq8ud7hVNYcfnVPJqcVpscN5So8BhtHuGYqET5BoDq63"; then
  "${CLEOS}" "${CLEOS_ARGS[@]}" wallet import --private-key "${DEV_PRIVATE_KEY}"
fi

SIKADEV_PRIVATE_KEY="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['accounts']['sikadev']['privateKey'])" 2>/dev/null || true)"
SIKADEV_PUBLIC_KEY="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['accounts']['sikadev']['publicKey'])" 2>/dev/null || true)"
if [[ -n "${SIKADEV_PRIVATE_KEY}" ]]; then
  SIKADEV_LEGACY="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['accounts']['sikadev'].get('publicKeyLegacy',''))" 2>/dev/null || true)"
  if ! "${CLEOS}" "${CLEOS_ARGS[@]}" wallet keys | grep -Eq "${SIKADEV_PUBLIC_KEY#PUB_K1_}|${SIKADEV_LEGACY}|${SIKADEV_PUBLIC_KEY}"; then
    echo "Importing sikadev dev key..."
    "${CLEOS}" "${CLEOS_ARGS[@]}" wallet import --private-key "${SIKADEV_PRIVATE_KEY}"
  fi
fi

echo ""
echo "Wallet ready. Example:"
echo "  cleos --url ${NODE_URL} --wallet-url ${WALLET_URL} create account eosio myaccount PUB_K1_..."
