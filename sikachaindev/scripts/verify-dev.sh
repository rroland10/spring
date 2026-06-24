#!/usr/bin/env bash
# Run SikaChainDev smoke checks (Ricardian, settlement, msig, economics).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

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

echo "SikaChainDev verify-dev (RPC: ${NODE_URL}, msig: ${MSIG_ACCOUNT})"

run "Ricardian ABIs" node "${SCRIPT_DIR}/verify-ricardian.mjs"
run "Settlement v0.2" bash "${SCRIPT_DIR}/verify-settlement-v0.2.sh"
run "Settlement economics" bash "${SCRIPT_DIR}/validate-settlement-economics.sh"

if [[ "${VERIFY_REX:-0}" == "1" ]]; then
  run "REX unstake" bash "${SCRIPT_DIR}/verify-rex-unstake.sh"
else
  echo ""
  echo "=== REX unstake ==="
  echo "SKIP (set VERIFY_REX=1 to run — includes cooldown wait)"
fi

if [[ "${VERIFY_TIER2:-0}" == "1" ]]; then
  run "Tier-2 vesting" env SIKA_VEST_SECONDS="${SIKA_VEST_SECONDS:-60}" bash "${SCRIPT_DIR}/verify-tier2-vesting.sh"
fi

if [[ "${SIKACHAIN_DEV:-}" == "1" ]]; then
  run "Phase 3 (sika system account)" bash "${SCRIPT_DIR}/verify-phase3.sh"
fi

if [[ "${VERIFY_ATOMICASSETS:-0}" == "1" ]]; then
  run "AtomicAssets" bash "${SCRIPT_DIR}/verify-atomicassets.sh"
  run "AtomicAssets mint" bash "${SCRIPT_DIR}/mint-nft-dev.sh"
fi

if [[ -n "$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json')).get('hyperionUrl','') or '')" 2>/dev/null)" ]]; then
  run "Hyperion indexer" bash "${SCRIPT_DIR}/check-hyperion.sh"
fi

echo ""
if [[ "${FAIL}" -eq 0 ]]; then
  echo "=== verify-dev complete — all checks passed ==="
else
  echo "=== verify-dev complete — one or more checks failed ===" >&2
  exit 1
fi
