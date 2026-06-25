#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${SIKA_DATA_DIR:-/var/lib/sikachain/data}"
CONFIG_DIR="${SIKA_CONFIG_DIR:-/var/lib/sikachain/config}"
GENESIS="${SIKA_GENESIS_JSON:-/etc/sikachain/genesis.json}"
NODEOS="${NODEOS_BIN:-/usr/local/bin/nodeos}"
TEMPLATE="${NODEOS_CONFIG_TEMPLATE:-/etc/sikachain/nodeos-producer.docker.ini}"

mkdir -p "${DATA_DIR}" "${CONFIG_DIR}"

BLOCKS_LOG="${DATA_DIR}/blocks/blocks.log"
if [[ -f "${BLOCKS_LOG}" ]]; then
  blksize="$(wc -c < "${BLOCKS_LOG}" | tr -d ' ')"
  if [[ "${blksize}" -lt 64 ]]; then
    echo "note: removing invalid blocks.log (${blksize} bytes) from failed start"
    rm -rf "${DATA_DIR}/blocks" "${DATA_DIR}/state"
  fi
fi

: "${PRODUCER_NAME:?set PRODUCER_NAME}"
: "${SIGNATURE_PROVIDER:?set SIGNATURE_PROVIDER (PUB=KEY:PVT)}"
: "${P2P_ADVERTISE:?set P2P_ADVERTISE (host:port advertised to peers)}"

export ENABLE_STALE_PRODUCTION="${ENABLE_STALE_PRODUCTION:-true}"
export MAX_TRANSACTION_TIME_MS="${MAX_TRANSACTION_TIME_MS:--1}"
export MAX_REVERSIBLE_BLOCKS="${MAX_REVERSIBLE_BLOCKS:-20000}"
export ABI_SERIALIZER_MAX_TIME_MS="${ABI_SERIALIZER_MAX_TIME_MS:-120000}"
export HTTP_MAX_RESPONSE_TIME_MS="${HTTP_MAX_RESPONSE_TIME_MS:-120000}"
export PRODUCER_NAME SIGNATURE_PROVIDER P2P_ADVERTISE
export P2P_MAX_PER_HOST="${P2P_MAX_PER_HOST:-16}"
export AGENT_NAME="${AGENT_NAME:-sikachain-testnet-${PRODUCER_NAME}}"
export CORS_ORIGIN="${CORS_ORIGIN:-*}"
export HTTP_VALIDATE_HOST="${HTTP_VALIDATE_HOST:-false}"

P2P_PEER_LINES=""
if [[ -n "${P2P_PEERS:-}" ]]; then
  IFS=',' read -ra PEERS <<< "${P2P_PEERS}"
  for peer in "${PEERS[@]}"; do
    peer="$(echo "${peer}" | xargs)"
    [[ -n "${peer}" ]] || continue
    P2P_PEER_LINES+="p2p-peer-address = ${peer}"$'\n'
  done
fi
export P2P_PEER_LINES

envsubst < "${TEMPLATE}" > "${CONFIG_DIR}/config.ini"

ARGS=(
  --config-dir "${CONFIG_DIR}"
  --data-dir "${DATA_DIR}"
)

if [[ ! -f "${DATA_DIR}/blocks/blocks.log" ]]; then
  if [[ ! -f "${GENESIS}" ]]; then
    echo "error: first start requires genesis JSON at ${GENESIS} (mount a real genesis file)" >&2
    exit 1
  fi
  ARGS+=(--genesis-json "${GENESIS}")
fi

if [[ -f "${DATA_DIR}/blocks/blocks.log" ]] && [[ ! -f "${DATA_DIR}/.clean_shutdown" ]]; then
  echo "note: unclean shutdown — replaying blockchain"
  ARGS+=(--replay-blockchain)
fi

echo "Starting nodeos as ${PRODUCER_NAME} (data=${DATA_DIR})"
exec "${NODEOS}" "${ARGS[@]}"
