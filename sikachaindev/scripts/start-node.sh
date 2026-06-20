#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/env.sh"
CONFIG_DIR="${ROOT}/config"
DATA_DIR="${ROOT}/data"
GENESIS="${CONFIG_DIR}/genesis.json"

if [[ "${SIKACHAIN_DEV:-}" == "1" ]]; then
  RUNTIME_CONFIG="${DATA_DIR}/runtime-config"
  mkdir -p "${RUNTIME_CONFIG}"
  sed "s/^producer-name = .*/producer-name = ${SIKA_SYSTEM_ACCOUNT}/" \
    "${CONFIG_DIR}/config.ini" > "${RUNTIME_CONFIG}/config.ini"
  CONFIG_DIR="${RUNTIME_CONFIG}"
fi

BUILD_BIN="${ROOT}/../build/programs"
if [[ -z "${NODEOS:-}" ]]; then
  if [[ -x "${BUILD_BIN}/nodeos/nodeos" ]]; then
    NODEOS="${BUILD_BIN}/nodeos/nodeos"
  else
    NODEOS="nodeos"
  fi
fi

if ! command -v "${NODEOS}" >/dev/null 2>&1 && [[ ! -x "${NODEOS}" ]]; then
  echo "error: nodeos not found. Install Spring or set NODEOS=/path/to/nodeos"
  exit 1
fi

mkdir -p "${DATA_DIR}"
LOG_FILE="${DATA_DIR}/nodeos.log"
PID_FILE="${DATA_DIR}/nodeos.pid"

NODEOS_ARGS=(
  --config-dir "${CONFIG_DIR}"
  --data-dir "${DATA_DIR}"
  --genesis-json "${GENESIS}"
)

if [[ "${1:-}" == "--daemon" ]] || [[ "${DAEMON:-}" == "1" ]]; then
  if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
    echo "nodeos already running (pid $(cat "${PID_FILE}"))"
    exit 0
  fi
  # Unclean shutdown leaves a dirty DB; replay on next start.
  if [[ -f "${DATA_DIR}/blocks/blocks.log" ]] && [[ ! -f "${DATA_DIR}/.clean_shutdown" ]]; then
    NODEOS_ARGS+=(--replay-blockchain)
    echo "note: replaying blockchain (previous unclean shutdown)"
  elif [[ -f "${DATA_DIR}/shared_memory.bin" ]] && [[ ! -f "${DATA_DIR}/.clean_shutdown" ]]; then
    NODEOS_ARGS+=(--replay-blockchain)
    echo "note: replaying blockchain (no clean-shutdown marker)"
  fi
  rm -f "${DATA_DIR}/.clean_shutdown"
  nohup "${NODEOS}" "${NODEOS_ARGS[@]}" >> "${LOG_FILE}" 2>&1 &
  NODE_PID=$!
  disown -h "${NODE_PID}" 2>/dev/null || disown "${NODE_PID}" 2>/dev/null || true
  echo "${NODE_PID}" > "${PID_FILE}"
  echo "nodeos started in background (pid $(cat "${PID_FILE}"), log ${LOG_FILE})"
  exit 0
fi

echo "Starting SikaChainDev (single-node dev chain)"
echo "  config: ${CONFIG_DIR}"
echo "  data:   ${DATA_DIR}"
echo "  RPC:    http://127.0.0.1:8888"
echo ""

exec "${NODEOS}" "${NODEOS_ARGS[@]}"
