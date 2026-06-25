#!/usr/bin/env bash
# Report whether Spring nodeos was built with -DSIKACHAIN=ON (Phase 3).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="${SCRIPT_DIR}/../../build"
CACHE="${BUILD}/CMakeCache.txt"

if [[ ! -f "${CACHE}" ]]; then
  echo "Spring build not found at ${BUILD} — run cmake in spring/build first"
  exit 1
fi

if grep -q '^SIKACHAIN:BOOL=ON' "${CACHE}" 2>/dev/null; then
  echo "SIKACHAIN=ON — protocol account sikaio (sikaio.null, sikaio.prods); system contract @ sika"
  NODEOS="${BUILD}/programs/nodeos/nodeos"
  if [[ -x "${NODEOS}" ]] && LC_ALL=C grep -a -q 'sikaio' "${NODEOS}" 2>/dev/null; then
    echo "nodeos binary includes sikaio (rebuilt after protocol rename)"
    exit 0
  fi
  if [[ -x "${NODEOS}" ]]; then
    echo "WARN: nodeos exists but predates sikaio rename — rebuild:"
    echo "  bash scripts/build-sikachain-spring.sh"
    exit 1
  fi
  echo "nodeos not built yet — run: bash scripts/build-sikachain-spring.sh"
  exit 1
fi

echo "SIKACHAIN=OFF in CMake cache — rebuild Spring (config.hpp uses sika unconditionally)"
echo "  bash scripts/build-sikachain-spring.sh"
exit 1
