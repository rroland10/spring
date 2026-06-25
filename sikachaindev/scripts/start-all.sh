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
  # SpringReloaded keosd on :8899 serves a different wallet dir — break signing.
  local kpid kcmd
  kpid="$(lsof -t -iTCP:8899 -sTCP:LISTEN 2>/dev/null | head -1 || true)"
  if [[ -n "${kpid}" ]]; then
    kcmd="$(ps -p "${kpid}" -o command= 2>/dev/null || true)"
    if ! echo "${kcmd}" | grep -q "${ROOT}/wallet"; then
      echo "error: port 8899 is in use by foreign keosd (pid ${kpid})" >&2
      echo "  ${kcmd}" >&2
      if [[ "${STOP_FOREIGN_NODEOS:-1}" == "1" ]]; then
        echo "Stopping foreign keosd (set STOP_FOREIGN_NODEOS=0 to disable)..." >&2
        kill -9 "${kpid}" 2>/dev/null || true
        sleep 1
      else
        exit 1
      fi
    fi
  fi

  if curl -sf "${WALLET_URL}/v1/wallet/list_wallets" >/dev/null 2>&1; then
    echo "keosd already running at ${WALLET_URL}"
    return
  fi
  KEOSD_PID="$(bash "${SCRIPT_DIR}/daemonize.sh" "${DATA_DIR}/keosd.log" "${KEOSD}" \
    --wallet-dir "${WALLET_DIR}" \
    --http-server-address 127.0.0.1:8899 \
    --unlock-timeout 9999999)"
  echo "${KEOSD_PID}" > "${DATA_DIR}/keosd.pid"
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
