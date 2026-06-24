#!/usr/bin/env bash
# Full Phase 3 verification gate: Spring build, smoke, contract tests, optional on-chain verify-dev.
#
# Usage:
#   export SIKACHAIN_DEV=1 SIKA_SYSTEM_ACCOUNT=sika
#   bash scripts/verify-all.sh              # fast gate (smoke + unit tests)
#   VERIFY_DEV=1 bash scripts/verify-all.sh # include verify-dev (on-chain txs)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

export SIKACHAIN_DEV="${SIKACHAIN_DEV:-1}"
export SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT:-sika}"

FAIL=0
run() {
  local label="$1"
  shift
  echo ""
  echo "=== ${label} ==="
  if "$@"; then
    echo "OK: ${label}"
  else
    echo "FAIL: ${label}" >&2
    FAIL=1
  fi
}

echo "=== verify-all (Phase 3) ==="
echo "  RPC: ${NODE_URL}  system: ${SIKA_SYSTEM_ACCOUNT}"

run "Spring SIKACHAIN build" bash "${SCRIPT_DIR}/check-spring-sikachain.sh"
run "Phase 3 smoke" bash "${SCRIPT_DIR}/smoke-phase3.sh"
run "Contract unit tests" bash "${SCRIPT_DIR}/run-contract-tests.sh"

if [[ "${VERIFY_DEV:-0}" == "1" ]]; then
  run "verify-dev (on-chain)" env VERIFY_ATOMICASSETS=1 VERIFY_REX="${VERIFY_REX:-0}" VERIFY_TIER2="${VERIFY_TIER2:-0}" bash "${SCRIPT_DIR}/verify-dev.sh"
else
  echo ""
  echo "=== verify-dev (on-chain) ==="
  echo "SKIP (set VERIFY_DEV=1 to run settlement/msig/NFT txs)"
fi

echo ""
if [[ "${FAIL}" -eq 0 ]]; then
  echo "=== verify-all complete — all checks passed ==="
else
  echo "=== verify-all complete — one or more checks failed ===" >&2
  exit 1
fi
