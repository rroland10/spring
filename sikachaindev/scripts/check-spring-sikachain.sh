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
  echo "SIKACHAIN=ON — privileged system account sika (sika.null, sika.prods)"
  exit 0
fi

echo "SIKACHAIN=OFF in CMake cache — rebuild Spring (config.hpp uses sika unconditionally)"
echo "  bash scripts/build-sikachain-spring.sh"
exit 1
