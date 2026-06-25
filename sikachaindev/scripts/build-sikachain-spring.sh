#!/usr/bin/env bash
# Rebuild Spring nodeos/cleos/keosd (protocol account = sikaio, system host = sika in config.hpp).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="${SCRIPT_DIR}/../../build"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

echo "Configuring Spring (SIKACHAIN=ON by default)..."
cmake -S "${BUILD}/.." -B "${BUILD}" -DSIKACHAIN=ON

echo "Building nodeos, cleos, keosd, sika_unit_tests..."
cmake --build "${BUILD}" --target nodeos cleos keosd sika_unit_tests -j"${JOBS}"

echo ""
echo "Done. Reset chain if upgrading from legacy eosio/sika-only genesis:"
echo "  cd \"sikachain sys contract/contracts\" && SIKACHAIN=1 ./build.sh"
echo "  bash scripts/bootstrap-phase3.sh --reset"
