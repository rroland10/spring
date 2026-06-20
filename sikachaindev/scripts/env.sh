#!/usr/bin/env bash
ENV_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${ENV_SH_DIR}/.." && pwd)"
BUILD_BIN="${ROOT}/../build/programs"
CHAIN_JSON="${ROOT}/chain.json"

export NODE_URL="${NODE_URL:-http://127.0.0.1:8888}"
export WALLET_URL="${WALLET_URL:-http://127.0.0.1:8899}"

if [[ -z "${CLEOS:-}" ]]; then
  if [[ -x "${BUILD_BIN}/cleos/cleos" ]]; then
    CLEOS="${BUILD_BIN}/cleos/cleos"
  else
    CLEOS="cleos"
  fi
fi

if [[ -z "${NODEOS:-}" ]]; then
  if [[ -x "${BUILD_BIN}/nodeos/nodeos" ]]; then
    NODEOS="${BUILD_BIN}/nodeos/nodeos"
  else
    NODEOS="nodeos"
  fi
fi

if [[ -z "${KEOSD:-}" ]]; then
  if [[ -x "${BUILD_BIN}/keosd/keosd" ]]; then
    KEOSD="${BUILD_BIN}/keosd/keosd"
  else
    KEOSD="keosd"
  fi
fi

cleos() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

if [[ "${SIKACHAIN_DEV:-}" == "1" ]]; then
  export SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT:-sika}"
  export SIKA_ACCOUNTS_JSON="${ROOT}/accounts.phase3.json"
else
  export SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT:-eosio}"
  export SIKA_ACCOUNTS_JSON="${ROOT}/accounts.json"
fi

export SIKA_APP_PORT="${SIKA_APP_PORT:-3003}"
export SIKA_APP_URL="${SIKA_APP_URL:-http://127.0.0.1:${SIKA_APP_PORT}}"
export SIKA_CHAIN_WEB_PORT="${SIKA_CHAIN_WEB_PORT:-3004}"
export SIKA_CHAIN_WEB_URL="${SIKA_CHAIN_WEB_URL:-http://127.0.0.1:${SIKA_CHAIN_WEB_PORT}}"
export SIKA_CHAIN_WEB_DIR="${SIKA_CHAIN_WEB_DIR:-/Users/randallroland/Desktop/Projects/SikaChain}"
