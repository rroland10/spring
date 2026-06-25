#!/usr/bin/env bash
# Build all Sika system contracts via Antelope CDT in Docker (no host CDT required).
#
# Output: contracts/build/contracts/<name>/{wasm,abi}
#
# Usage:
#   bash build-sika-contracts-docker.sh
#   bash build-sika-contracts-docker.sh sika.treas   # single target
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTRACTS_DIR="${SIKA_CONTRACTS_DIR:-/Users/randallroland/Desktop/Projects/sikachain sys contract/contracts}"
TARGET="${1:-all}"

SIKACHAIN_CMAKE_FLAGS=""
if [[ "${SIKACHAIN:-}" == "1" ]]; then
  SIKACHAIN_CMAKE_FLAGS=" -DSIKACHAIN=ON"
  echo "Building contracts with SIKACHAIN=1 (SYSTEM account = sika)"
fi
export SIKACHAIN_CMAKE_FLAGS

docker run --rm --platform linux/amd64 \
  -v "${CONTRACTS_DIR}:/work" \
  -w /work \
  ubuntu:22.04 bash -c "
    set -e
    apt-get update -qq && apt-get install -qq -y wget cmake make g++ > /dev/null
    if ! command -v cdt-cpp >/dev/null 2>&1; then
      wget -q https://github.com/AntelopeIO/cdt/releases/download/v4.1.1/cdt_4.1.1-1_amd64.deb -O /tmp/cdt.deb
      apt-get install -qq -y /tmp/cdt.deb > /dev/null
    fi
    export PATH=/usr/bin:\$PATH
    BUILD_DIR=\"/work/.docker-build-\$(date +%s)\"
    mkdir -p \"\${BUILD_DIR}\" && cd \"\${BUILD_DIR}\"
    cmake /work -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE=/usr/lib/cmake/cdt/CDTWasmToolchain.cmake \
      -Dcdt_DIR=/usr/lib/cmake/cdt${SIKACHAIN_CMAKE_FLAGS:-}
    if [[ '${TARGET}' == 'all' ]]; then
      make -j2
    else
      make -j2 '${TARGET}'
    fi
    mkdir -p /work/build/contracts
    for c in sika.system sika.token sika.rep sika.guard sika.rules sika.issue sika.treas; do
      if [[ -f contracts/\${c}/\${c}.wasm ]]; then
        mkdir -p /work/build/contracts/\${c}
        cp contracts/\${c}/\${c}.wasm contracts/\${c}/\${c}.abi /work/build/contracts/\${c}/
      fi
    done
    rm -rf \"\${BUILD_DIR}\"
  "

echo "=== Contract build complete ==="
for c in sika.system sika.token sika.rep sika.guard sika.rules sika.issue sika.treas; do
  wasm="${CONTRACTS_DIR}/build/contracts/${c}/${c}.wasm"
  if [[ -f "${wasm}" ]]; then
    size=$(stat -f '%z' "${wasm}" 2>/dev/null || stat -c '%s' "${wasm}")
    echo "  ${c}.wasm (${size} bytes)"
  else
    echo "  ${c}.wasm MISSING"
  fi
done
