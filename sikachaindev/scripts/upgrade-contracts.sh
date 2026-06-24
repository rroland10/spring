#!/usr/bin/env bash
# Publish latest Sika contract WASM to a running SikaChainDev node (no genesis bootstrap).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTRACTS_DIR="${SIKA_CONTRACTS_DIR:-/Users/randallroland/Desktop/Projects/sikachain sys contract/contracts}"
BUILD_DIR="${CONTRACTS_DIR}/build/contracts"

need_build=0
for wasm in sika.token sika.system sika.rep sika.guard sika.rules sika.issue sika.treas; do
  if [[ ! -f "${BUILD_DIR}/${wasm}/${wasm}.wasm" ]]; then
    need_build=1
    break
  fi
done

if [[ "${need_build}" -eq 1 ]]; then
  echo "Missing contract artifacts — building via Docker CDT..."
  bash "${SCRIPT_DIR}/build-sika-contracts-docker.sh"
fi

export SIKA_UPGRADE_ONLY=1
exec bash "${SCRIPT_DIR}/deploy-sika-system.sh"
