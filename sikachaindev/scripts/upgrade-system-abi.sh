#!/usr/bin/env bash
# Publish patched sika.system ABI (adds delband for wallet get_table_rows) without WASM change.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

CONTRACTS_DIR="${SIKA_CONTRACTS_DIR:-/Users/randallroland/Desktop/Projects/sikachain sys contract/contracts}"
ABI="${CONTRACTS_DIR}/build/contracts/sika.system/sika.system.abi"

if [[ ! -f "${ABI}" ]]; then
  echo "error: missing ${ABI} — run build-sika-contracts-docker.sh first"
  exit 1
fi

bash "${SCRIPT_DIR}/wait-for-rpc.sh" 60
node "${SCRIPT_DIR}/patch-system-abi.mjs" "${ABI}"

echo "Setting ABI on ${SIKA_SYSTEM_ACCOUNT}..."
cleos_tx() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}
cleos_tx set abi "${SIKA_SYSTEM_ACCOUNT}" "${ABI}"

echo "OK: ${SIKA_SYSTEM_ACCOUNT} ABI updated (delband table queryable)"

if [[ "${1:-}" != "--no-smoke" ]]; then
  bash "${SCRIPT_DIR}/smoke-wallet.sh" sikadev
fi
