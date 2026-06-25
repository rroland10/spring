#!/usr/bin/env bash
# Build Spring eosio.boot (protocol feature activation) for SikaChainDev deploy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONTRACTS_SRC="${ROOT}/../.system-contracts/contracts"
BUILD_DIR="${CONTRACTS_SRC}/build"
SPRING_BUILD="${ROOT}/../build"

if [[ ! -d "${CONTRACTS_SRC}" ]]; then
  echo "error: ${CONTRACTS_SRC} not found"
  exit 1
fi

if ! command -v cdt-cpp >/dev/null 2>&1; then
  echo "error: cdt-cpp not found — install Antelope CDT or use Docker quorum-cdt for Sika contracts"
  exit 1
fi

mkdir -p "${BUILD_DIR}"
if [[ ! -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
  cmake -S "${CONTRACTS_SRC}" -B "${BUILD_DIR}" \
    -DEOSIO_WASM_OLD_BEHAVIOR=OFF \
    -DCMAKE_TOOLCHAIN_FILE="${SPRING_BUILD}/lib/cmake/eosio.cdt/EosioWasmToolchain.cmake" 2>/dev/null \
    || cmake -S "${CONTRACTS_SRC}" -B "${BUILD_DIR}"
fi

cmake --build "${BUILD_DIR}" --target eosio.boot -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "Built: ${BUILD_DIR}/eosio.boot/eosio.boot.wasm"
