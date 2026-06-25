#!/usr/bin/env bash
# Start full SikaChainDev ecosystem: chain + Hyperion + wallet + site + API.
#
# Usage:
#   export SIKACHAIN_DEV=1 SIKA_PROTOCOL_ACCOUNT=sikaio SIKA_SYSTEM_ACCOUNT=sika
#   bash scripts/start-ecosystem.sh          # bootstrap if needed + all services
#   bash scripts/start-ecosystem.sh --quick  # chain + apps only (skip bootstrap)
#   bash scripts/start-ecosystem.sh --verify # run verify-dev after startup
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

DATA_DIR="${ROOT}/data"
mkdir -p "${DATA_DIR}"

export SIKACHAIN_DEV="${SIKACHAIN_DEV:-1}"
export SIKA_PROTOCOL_ACCOUNT="${SIKA_PROTOCOL_ACCOUNT:-sikaio}"
export SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT:-sika}"
export ENABLE_SHIP="${ENABLE_SHIP:-1}"

APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
WEB_DIR="${SIKA_CHAIN_WEB_DIR:-/Users/randallroland/Desktop/Projects/SikaChain}"
ADAPTER_DIR="${SIKA_ADAPTER_DIR:-/Users/randallroland/Desktop/Projects/wharfkit adapter}"

port_up() {
  local port="$1"
  lsof -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
}

start_bg() {
  local label="$1"
  local port="$2"
  local log="$3"
  shift 3
  if port_up "${port}"; then
    echo "  (running) ${label} :${port}"
    return 0
  fi
  bash "${SCRIPT_DIR}/daemonize.sh" "${log}" "$@" >/dev/null
  echo "  started ${label} :${port} (log ${log})"
}

echo "=== SikaChainDev ecosystem ==="
echo "  Phase 3: SIKACHAIN_DEV=${SIKACHAIN_DEV}  protocol=${SIKA_PROTOCOL_ACCOUNT}  system=${SIKA_SYSTEM_ACCOUNT}"
echo ""

QUICK=0
VERIFY=0
for arg in "$@"; do
  case "${arg}" in
    --quick) QUICK=1 ;;
    --verify) VERIFY=1 ;;
  esac
done

if [[ "${QUICK}" -eq 1 ]]; then
  bash "${SCRIPT_DIR}/start-all.sh"
  bash "${SCRIPT_DIR}/setup-wallet.sh"
  bash "${SCRIPT_DIR}/sync-dev-env.sh" 2>/dev/null || true
  [[ -f "${APP_DIR}/.env.sikachaindev.phase3" ]] && \
    cp "${APP_DIR}/.env.sikachaindev.phase3" "${APP_DIR}/.env.local"
  [[ -f "${WEB_DIR}/scripts/sync-chain-config.mjs" ]] && \
    node "${WEB_DIR}/scripts/sync-chain-config.mjs" 2>/dev/null || true
  if curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null 2>&1; then
    bash "${SCRIPT_DIR}/create-dev-accounts.sh" 2>/dev/null \
      || echo "  note: create-dev-accounts skipped (run manually if peer wallets missing)"
  fi
else
  bash "${SCRIPT_DIR}/dev-ready.sh"
fi

echo ""
if ! bash "${SCRIPT_DIR}/wait-for-rpc.sh" 360; then
  echo "warning: RPC not ready yet — nodeos may still be replaying (tail -f ${DATA_DIR}/nodeos.log)"
fi

if "${CLEOS}" --url "${NODE_URL}" get table "${SIKA_SYSTEM_ACCOUNT}" "${SIKA_SYSTEM_ACCOUNT}" producers -l 3 2>/dev/null \
  | grep -q sikabpa; then
  echo "Aligning 6-BP dev schedule..."
  if BP_CLUSTER_SIZE=6 bash "${SCRIPT_DIR}/vote-bp-schedule.sh" >/dev/null 2>&1; then
    echo "  ok  6-BP vote schedule (sikabpa–sikabpf)"
  else
    echo "  note: vote-bp-schedule skipped (wallet locked?)"
  fi
fi

if command -v docker >/dev/null 2>&1 && [[ -f "${ROOT}/hyperion/docker-compose.yml" ]]; then
  hyperion_ok() {
    curl -sf "http://127.0.0.1:7001/v2/health" 2>/dev/null | python3 -c "
import sys, json
h = json.load(sys.stdin)
s = {x['service']: x['status'] for x in h.get('health', [])}
sys.exit(0 if s.get('NodeosRPC') == 'OK' and s.get('StateHistory') == 'OK' else 1)
" 2>/dev/null
  }
  if hyperion_ok; then
    echo "Hyperion healthy (NodeosRPC + StateHistory OK)"
  elif curl -sf "http://127.0.0.1:7001/v2/health" >/dev/null 2>&1; then
    echo "Restarting Hyperion (reconnect to nodeos SHIP)..."
    docker restart sikachaindev-hyperion-api sikachaindev-hyperion-indexer 2>/dev/null || true
    sleep 12
    hyperion_ok && echo "  ok  Hyperion reconnected" || echo "  note: Hyperion still warming — bash scripts/start-hyperion.sh"
  else
    echo "Starting Hyperion..."
    bash "${SCRIPT_DIR}/start-hyperion.sh" 2>&1 | tail -5 || echo "  (Hyperion start skipped — see start-hyperion.sh)"
  fi
fi

echo ""
echo "Starting apps..."
bash "${SCRIPT_DIR}/ensure-adapter.sh" 2>/dev/null || echo "  note: adapter restore skipped (see ensure-adapter.sh)"
start_bg "Sika app" "${SIKA_APP_PORT}" "${DATA_DIR}/sika-app.log" \
  bash -c "cd \"${APP_DIR}\" && npm run dev"

start_bg "SikaChain site" "${SIKA_CHAIN_WEB_PORT}" "${DATA_DIR}/sikachain-web.log" \
  bash -c "cd \"${WEB_DIR}\" && npm run dev -- -p ${SIKA_CHAIN_WEB_PORT}"

start_bg "Wharfkit adapter" 4000 "${DATA_DIR}/adapter.log" \
  bash -c "cd \"${ADAPTER_DIR}\" && npm run dev"

echo ""
sleep 4
bash "${SCRIPT_DIR}/ecosystem-status.sh" 2>/dev/null || bash "${SCRIPT_DIR}/status.sh"

echo ""
echo "=== URLs ==="
echo "  Chain RPC:  ${NODE_URL}"
echo "  Wallet:     ${SIKA_APP_URL}"
echo "  Website:    ${SIKA_CHAIN_WEB_URL}"
echo "  API:        http://127.0.0.1:4000"
echo "  Hyperion:   $(python3 -c "import json; print(json.load(open('${ROOT}/chain.json')).get('hyperionUrl','(not configured)'))" 2>/dev/null)"
echo "  Verify:     bash scripts/quick-verify.sh  |  VERIFY_UI=0 bash scripts/verify-stack.sh"

if [[ "${VERIFY}" -eq 1 ]]; then
  echo ""
  echo "=== verify-stack (no Playwright — app may still be compiling) ==="
  VERIFY_UI=0 VERIFY_DEV=1 VERIFY_REX=1 VERIFY_TIER2=1 \
    bash "${SCRIPT_DIR}/verify-stack.sh"
fi
