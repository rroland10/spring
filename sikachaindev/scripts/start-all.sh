#!/usr/bin/env bash
# Start keosd + nodeos for SikaChainDev (both as background daemons).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

DATA_DIR="${ROOT}/data"
WALLET_DIR="${ROOT}/wallet"
mkdir -p "${DATA_DIR}" "${WALLET_DIR}"

start_keosd() {
  if curl -sf "${WALLET_URL}/v1/wallet/list_wallets" >/dev/null 2>&1; then
    echo "keosd already running at ${WALLET_URL}"
    return
  fi
  nohup "${KEOSD}" \
    --wallet-dir "${WALLET_DIR}" \
    --http-server-address 127.0.0.1:8899 \
    --unlock-timeout 9999999 \
    >> "${DATA_DIR}/keosd.log" 2>&1 &
  KEOSD_PID=$!
  disown -h "${KEOSD_PID}" 2>/dev/null || disown "${KEOSD_PID}" 2>/dev/null || true
  echo $! > "${DATA_DIR}/keosd.pid"
  for _ in $(seq 1 20); do
    curl -sf "${WALLET_URL}/v1/wallet/list_wallets" >/dev/null 2>&1 && break
    sleep 0.5
  done
  echo "keosd started (pid $(cat "${DATA_DIR}/keosd.pid"), log ${DATA_DIR}/keosd.log)"
}

start_keosd
bash "${SCRIPT_DIR}/start-node.sh" --daemon

echo ""
echo "SikaChainDev:"
echo "  RPC:    ${NODE_URL}"
echo "  Wallet: ${WALLET_URL}"
echo "  Setup:  ${SCRIPT_DIR}/setup-wallet.sh"
echo "  Deploy: ${SCRIPT_DIR}/deploy-sika-system.sh"
