#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
CONFIG_DIR="${ROOT}/config"
DATA_DIR="${ROOT}/data"
GENESIS="${CONFIG_DIR}/genesis.json"

if [[ "${SIKACHAIN_DEV:-}" == "1" ]]; then
  RUNTIME_CONFIG="${DATA_DIR}/runtime-config"
  mkdir -p "${RUNTIME_CONFIG}"
  if [[ ! -f "${RUNTIME_CONFIG}/config.ini" ]] || [[ "${RESET_RUNTIME_CONFIG:-}" == "1" ]]; then
    sed "s/^producer-name = .*/producer-name = ${SIKA_PROTOCOL_ACCOUNT:-sikaio}/" \
      "${CONFIG_DIR}/config.ini" > "${RUNTIME_CONFIG}/config.ini"
  fi
  CONFIG_DIR="${RUNTIME_CONFIG}"
fi

if [[ "${ENABLE_SHIP:-0}" == "1" ]]; then
  RUNTIME_CONFIG="${DATA_DIR}/runtime-config"
  mkdir -p "${RUNTIME_CONFIG}"
  if [[ "${CONFIG_DIR}" != "${RUNTIME_CONFIG}" ]]; then
    cp "${CONFIG_DIR}/config.ini" "${RUNTIME_CONFIG}/config.ini"
    CONFIG_DIR="${RUNTIME_CONFIG}"
  fi
  if ! grep -q 'state_history_plugin' "${CONFIG_DIR}/config.ini" 2>/dev/null; then
    cat >> "${CONFIG_DIR}/config.ini" <<'EOF'

# SHIP / Hyperion (ENABLE_SHIP=1) — see docs/hyperion-dev.md
plugin = eosio::state_history_plugin
disable-replay-opts = true
chain-state-history = true
trace-history = true
state-history-endpoint = 0.0.0.0:8080
EOF
    echo "note: state_history_plugin enabled (SHIP on 0.0.0.0:8080)"
  fi
  # Docker Hyperion reaches host via host.docker.internal — bind RPC/SHIP on all interfaces.
  sed -i '' 's/^http-server-address = .*/http-server-address = 0.0.0.0:8888/' "${CONFIG_DIR}/config.ini" 2>/dev/null || \
    sed -i 's/^http-server-address = .*/http-server-address = 0.0.0.0:8888/' "${CONFIG_DIR}/config.ini"
  sed -i '' 's/^state-history-endpoint = .*/state-history-endpoint = 0.0.0.0:8080/' "${CONFIG_DIR}/config.ini" 2>/dev/null || \
    sed -i 's/^state-history-endpoint = .*/state-history-endpoint = 0.0.0.0:8080/' "${CONFIG_DIR}/config.ini"
  if ! grep -q '^http-validate-host' "${CONFIG_DIR}/config.ini" 2>/dev/null; then
    echo "http-validate-host = false" >> "${CONFIG_DIR}/config.ini"
  else
    sed -i '' 's/^http-validate-host = .*/http-validate-host = false/' "${CONFIG_DIR}/config.ini" 2>/dev/null || \
      sed -i 's/^http-validate-host = .*/http-validate-host = false/' "${CONFIG_DIR}/config.ini"
  fi
fi

ensure_browser_cors() {
  local cfg="${1}"
  if grep -q '^access-control-allow-origin' "${cfg}" 2>/dev/null; then
    return 0
  fi
  cat >> "${cfg}" <<'EOF'

# Browser wallet UI (Sika app :3003, Anchor, WharfKit)
access-control-allow-origin = *
access-control-allow-headers = Content-Type,Accept,Authorization,X-Requested-With
access-control-allow-credentials = true
EOF
}

ensure_browser_cors "${CONFIG_DIR}/config.ini"

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
  NODE_PID="$(bash "${SCRIPT_DIR}/daemonize.sh" "${LOG_FILE}" "${NODEOS}" "${NODEOS_ARGS[@]}")"
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
