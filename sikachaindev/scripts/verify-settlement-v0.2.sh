#!/usr/bin/env bash
# Smoke-test BP compensation & settlement v0.2 on SikaChainDev.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

SIKA_SYSTEM="${SIKA_SYSTEM_ACCOUNT:-sika}"
PRODUCER="${SETTLEMENT_TEST_BP:-sikabpa}"

cleos_cmd() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

cleos_push() {
  cleos_cmd push action "$@" -x 3600
}

unlock_wallet() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet open 2>/dev/null || true
  if [[ -f "${ROOT}/wallet/.password" ]]; then
    local pw
    pw="$(tr -d '\n' < "${ROOT}/wallet/.password")"
    "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet unlock --password "${pw}" 2>/dev/null || true
  fi
}

assert_contains() {
  local hay="$1"
  local needle="$2"
  local label="$3"
  if ! echo "${hay}" | grep -q "${needle}"; then
    echo "FAIL: ${label} — expected '${needle}' in output" >&2
    echo "${hay}" >&2
    exit 1
  fi
  echo "OK: ${label}"
}

unlock_wallet

echo "=== 1. Oracle FX push (CGHS) ==="
if command -v node >/dev/null 2>&1 && [[ -f "${SCRIPT_DIR}/oracle-push-fx.mjs" ]]; then
  if [[ "${ORACLE_REQUIRE_SIGNED:-0}" == "1" ]]; then
    ORACLE_CFG=$(cleos_cmd get table sika.treas sika.treas oraclecfg 2>/dev/null || echo "{}")
    if ! echo "${ORACLE_CFG}" | grep -q '"require_signed_push": 1'; then
      echo "FAIL: ORACLE_REQUIRE_SIGNED=1 but oraclecfg.require_signed_push is not enabled" >&2
      echo "${ORACLE_CFG}" >&2
      exit 1
    fi
    if [[ -z "${ORACLE_SIGN_KEY:-}" ]]; then
      echo "FAIL: ORACLE_REQUIRE_SIGNED=1 requires ORACLE_SIGN_KEY for pushfxsig" >&2
      exit 1
    fi
  fi
  PUSH_OUT=$(node "${SCRIPT_DIR}/oracle-push-fx.mjs" 2>&1) || {
    if [[ "${ORACLE_REQUIRE_SIGNED:-0}" == "1" ]]; then
      echo "FAIL: signed oracle push failed" >&2
      echo "${PUSH_OUT}" >&2
      exit 1
    fi
    echo "WARN: oracle push skipped (chain may use setfx peg)"
    PUSH_OUT=""
  }
  if [[ "${ORACLE_REQUIRE_SIGNED:-0}" == "1" && -n "${PUSH_OUT}" ]]; then
    assert_contains "${PUSH_OUT}" '"mode": "pushfxsig"' "signed pushfxsig"
  fi
  FX_ROW=$(cleos_cmd get table sika.treas sika.treas fxquotes -l 10 2>/dev/null || true)
  if echo "${FX_ROW}" | grep -q '"cusd_ppm"'; then
    echo "OK: fxquotes row present"
  else
    if [[ "${ORACLE_REQUIRE_SIGNED:-0}" == "1" ]]; then
      echo "FAIL: ORACLE_REQUIRE_SIGNED=1 but fxquotes row missing after push" >&2
      exit 1
    fi
    echo "WARN: no fxquotes row — sweep uses 1:1 dev peg fallback"
  fi
else
  echo "SKIP: node/oracle script unavailable"
fi

YIELD_BEFORE=$(cleos_cmd get table "${SIKA_SYSTEM}" "${SIKA_SYSTEM}" rexpool 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin).get('rows',[])
print(rows[0].get('cghs_yield_pool','0.0000 CUSD') if rows else '0.0000 CUSD')
" || echo "0.0000 CUSD")

echo "=== 2. Fee accrual + sweep (fresh market: ng) ==="
# Use a dedicated verify market so repeated runs still hit an unswept tranche.
SWEEP_MARKET="${SETTLEMENT_VERIFY_MARKET:-ng}"
SWEEP_LOG=$(bash "${SCRIPT_DIR}/settlement-sweep.sh" "${SWEEP_MARKET}" "5000.0000 CGHS" 2>&1) || true
echo "${SWEEP_LOG}"
if echo "${SWEEP_LOG}" | grep -qE "yield [0-9]"; then
  echo "OK: sweep routed fee slice to credyield"
elif echo "${SWEEP_LOG}" | grep -q "nothing to sweep"; then
  echo "WARN: sweep idempotent (ledger already caught up for ${SWEEP_MARKET})"
else
  echo "WARN: could not confirm yield routing from sweep output"
fi

YIELD_AFTER=$(cleos_cmd get table "${SIKA_SYSTEM}" "${SIKA_SYSTEM}" rexpool 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin).get('rows',[])
print(rows[0].get('cghs_yield_pool','0.0000 CGHS') if rows else '0.0000 CGHS')
" || echo "0.0000 CGHS")
echo "cghs_yield_pool: ${YIELD_BEFORE} → ${YIELD_AFTER}"

echo "=== 3. Cross-market subsidize (gh → tz) ==="
cleos_push sika.treas accruefee '["tz","2000.0000 CGHS"]' -p "${SIKA_SYSTEM}@active" || true
if cleos_push sika.treas subsidize '["gh","tz","1.0000 CUSD"]' -p "${SIKA_SYSTEM}@active" 2>&1; then
  echo "OK: subsidize"
else
  echo "WARN: subsidize skipped (donor cap / ledger — fund gh sweep first)"
fi

echo "=== 4. Tier-1 claimprod (CUSD paycost) ==="
RESERVE_BEFORE=$(cleos_cmd get table sika.treas sika.treas reserve 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin).get('rows',[])
print(rows[0]['cusd_balance'] if rows else '0.0000 CUSD')
" || echo "unknown")
cleos_push "${SIKA_SYSTEM}" claimprod "[\"${PRODUCER}\"]" -p "${PRODUCER}@active" || true
RESERVE_AFTER=$(cleos_cmd get table sika.treas sika.treas reserve 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin).get('rows',[])
print(rows[0]['cusd_balance'] if rows else '0.0000 CUSD')
" || echo "unknown")
echo "reserve: ${RESERVE_BEFORE} → ${RESERVE_AFTER}"

echo "=== 5. Reserve rebalance (cUSD / gGOLD split) ==="
cleos_push sika.treas rebalance '[]' -p "${SIKA_SYSTEM}@active"

echo "=== 6. Optional Tier-2 vesting ==="
if cleos_cmd get table "${SIKA_SYSTEM}" "${SIKA_SYSTEM}" vestglb 2>/dev/null | grep -q '"tier2_vesting_enabled": 1'; then
  echo "vesting enabled — claimprod should escrow Tier-2 SIKA"
  cleos_push "${SIKA_SYSTEM}" claimvest "[\"${PRODUCER}\"]" -p "${PRODUCER}@active" || true
else
  echo "vesting disabled (set TIER2_VESTING_ENABLE=1 on deploy to exercise)"
fi

echo "=== 7. Market payout prefs (§6.4) ==="
if command -v node >/dev/null 2>&1 && [[ -f "${SCRIPT_DIR}/seed-marketprefs.mjs" ]]; then
  node "${SCRIPT_DIR}/seed-marketprefs.mjs" 2>&1 || true
  PREFS=$(cleos_cmd get table sika.treas sika.treas marketpref -l 10 2>/dev/null || true)
  if echo "${PREFS}" | grep -q '"market": "gh"'; then
    echo "OK: marketpref rows present"
  else
    echo "WARN: marketpref table empty — upgrade sika.treas WASM first"
  fi
else
  echo "SKIP: seed-marketprefs unavailable"
fi

echo "=== 8. Multisig (${MSIG_ACCOUNT:-sika.msig}) ==="
if [[ -f "${SCRIPT_DIR}/verify-msig.sh" ]]; then
  bash "${SCRIPT_DIR}/verify-msig.sh" || echo "WARN: verify-msig failed — run deploy-msig.sh"
else
  echo "SKIP: verify-msig.sh missing"
fi

if [[ -f "${SCRIPT_DIR}/verify-msig-business.sh" ]]; then
  bash "${SCRIPT_DIR}/verify-msig-business.sh" || echo "WARN: verify-msig-business failed"
else
  echo "SKIP: verify-msig-business.sh missing"
fi

echo "=== verify-settlement-v0.2 complete ==="
