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
