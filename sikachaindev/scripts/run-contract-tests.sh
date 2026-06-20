#!/usr/bin/env bash
# Run SikaChain C++ contract tests (requires Spring build + contract WASMs).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONTRACTS="${SIKA_CONTRACTS_DIR:-/Users/randallroland/Desktop/Projects/sikachain sys contract/contracts}"
SPRING_BUILD="${SPRING_BUILD_PATH:-${ROOT}/../build}"
TEST_BIN="${SPRING_BUILD}/sikachain-tests/sika_unit_tests"

if [[ -x "${TEST_BIN}" ]]; then
  exec "${TEST_BIN}" --log_level=test_suite --color_output=true
fi

if [[ -f "${CONTRACTS}/build-tests.sh" ]]; then
  exec bash "${CONTRACTS}/build-tests.sh"
fi

echo "error: sika_unit_tests not found — build Spring with sikachain-tests (cmake .. && make sika_unit_tests)"
exit 1
