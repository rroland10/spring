#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WALLET_DIR="${ROOT}/wallet"

BUILD_BIN="${ROOT}/../build/programs"
if [[ -z "${KEOSD:-}" ]]; then
  if [[ -x "${BUILD_BIN}/keosd/keosd" ]]; then
    KEOSD="${BUILD_BIN}/keosd/keosd"
  else
    KEOSD="keosd"
  fi
fi

if ! command -v "${KEOSD}" >/dev/null 2>&1 && [[ ! -x "${KEOSD}" ]]; then
  echo "error: keosd not found. Install Spring or set KEOSD=/path/to/keosd"
  exit 1
fi

mkdir -p "${WALLET_DIR}"

echo "Starting keosd for SikaChainDev"
echo "  wallet: ${WALLET_DIR}"
echo "  URL:    http://127.0.0.1:8899"
echo ""

exec "${KEOSD}" \
  --wallet-dir "${WALLET_DIR}" \
  --http-server-address 127.0.0.1:8899 \
  --unlock-timeout 9999999
