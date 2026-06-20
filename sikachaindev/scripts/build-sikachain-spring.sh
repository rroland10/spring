#!/usr/bin/env bash
# Rebuild Spring nodeos/cleos/keosd with SIKACHAIN=ON (privileged account = sika).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="${SCRIPT_DIR}/../../build"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

echo "Configuring Spring with -DSIKACHAIN=ON..."
cmake -S "${BUILD}/.." -B "${BUILD}" -DSIKACHAIN=ON

echo "Building nodeos, cleos, keosd, sika_unit_tests..."
cmake --build "${BUILD}" --target nodeos cleos keosd sika_unit_tests -j"${JOBS}"

echo ""
echo "Done. Rebuild contracts and reset for Phase 3:"
echo "  cd \"sikachain sys contract/contracts\" && SIKACHAIN=1 ./build.sh"
echo "  export SIKACHAIN_DEV=1"
echo "  SIKA_RESET_CONFIRM=yes bash scripts/reset-chain.sh"
echo "  bash scripts/bootstrap-dev.sh"
