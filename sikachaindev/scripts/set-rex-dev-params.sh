#!/usr/bin/env bash
# Dev-only: shorten REX unstake cool-down for local testing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

SIKA_SYSTEM="${SIKA_SYSTEM_ACCOUNT:-sika}"
SECONDS="${REX_UNSTAKE_SECONDS:-60}"

"${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet open 2>/dev/null || true
if [[ -f "${ROOT}/wallet/.password" ]]; then
  pw="$(tr -d '\n' < "${ROOT}/wallet/.password")"
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet unlock --password "${pw}" 2>/dev/null || true
fi

echo "Setting REX unstake window to ${SECONDS}s (setrexcfg)..."
"${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" push action "${SIKA_SYSTEM}" setrexcfg \
  "[\"${SIKA_SYSTEM}\",${SECONDS}]" -p "${SIKA_SYSTEM}@active" -x 3600

"${CLEOS}" --url "${NODE_URL}" get table "${SIKA_SYSTEM}" "${SIKA_SYSTEM}" rexcfg 2>/dev/null || true
