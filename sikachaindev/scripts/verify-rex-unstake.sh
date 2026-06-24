#!/usr/bin/env bash
# Smoke-test REX stake → sellrex → refund (uses dev-short unstake window).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

SIKA_SYSTEM="${SIKA_SYSTEM_ACCOUNT:-sika}"
TOKEN="${SIKA_TOKEN_ACCOUNT:-sika.token}"
ACTOR="${REX_TEST_ACCOUNT:-sikadev}"
STAKE="${REX_TEST_STAKE:-100.0000 SIKA}"
COOLDOWN="${REX_UNSTAKE_SECONDS:-5}"
WAIT=$(( COOLDOWN + 2 ))

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

unlock_wallet

read_rex_shares() {
  cleos_cmd get table "${SIKA_SYSTEM}" "${SIKA_SYSTEM}" rexbal -l 100 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin).get('rows',[])
for r in rows:
  if r.get('owner')=='${ACTOR}':
    print(r['rex_balance'].split()[0])
    break
else:
  print('0')
" || echo "0"
}

read_sika_balance() {
  cleos_cmd get currency balance "${TOKEN}" "${ACTOR}" SIKA 2>/dev/null | awk '{print $1}' || echo "0"
}

# Clear matured refunds from prior runs so buy/sell targets this test only.
for _ in $(seq 1 3); do
  cleos_push "${SIKA_SYSTEM}" refund "[\"${ACTOR}\"]" -p "${ACTOR}@active" 2>/dev/null || true
  sleep 1
done

echo "=== 1. Dev REX cooldown (${COOLDOWN}s) ==="
REX_UNSTAKE_SECONDS="${COOLDOWN}" bash "${SCRIPT_DIR}/set-rex-dev-params.sh"

REX_BEFORE="$(read_rex_shares)"

echo "=== 2. buyrex ${STAKE} as ${ACTOR} ==="
cleos_push "${SIKA_SYSTEM}" buyrex "[\"${ACTOR}\",\"${STAKE}\"]" -p "${ACTOR}@active"

REX_AFTER="${REX_BEFORE}"
for _ in $(seq 1 60); do
  REX_AFTER="$(read_rex_shares)"
  if python3 -c "import sys; sys.exit(0 if float('${REX_AFTER}') > float('${REX_BEFORE}') else 1)"; then
    break
  fi
  sleep 0.5
done

REX_SHARES=$(python3 -c "before=float('${REX_BEFORE}'); after=float('${REX_AFTER}'); print(f'{after - before:.4f}')")

if python3 -c "import sys; sys.exit(0 if float('${REX_SHARES}') > 0 else 1)"; then
  :
else
  echo "FAIL: buyrex did not increase REX balance for ${ACTOR}" >&2
  exit 1
fi
echo "REX shares (this test): ${REX_SHARES}"

echo "=== 3. sellrex ==="
cleos_push "${SIKA_SYSTEM}" sellrex "[\"${ACTOR}\",\"${REX_SHARES} REX\"]" -p "${ACTOR}@active"

echo "=== 4. refund (expect fail before cooldown) ==="
if cleos_push "${SIKA_SYSTEM}" refund "[\"${ACTOR}\"]" -p "${ACTOR}@active" 2>/dev/null; then
  echo "WARN: refund succeeded immediately (cooldown may already be zero)"
else
  echo "OK: refund blocked during cooldown"
fi

echo "=== 5. wait ${WAIT}s ==="
sleep "${WAIT}"

BAL_BEFORE=$(read_sika_balance)
cleos_push "${SIKA_SYSTEM}" refund "[\"${ACTOR}\"]" -p "${ACTOR}@active"

BAL_AFTER="${BAL_BEFORE}"
for _ in $(seq 1 120); do
  BAL_AFTER=$(read_sika_balance)
  if python3 -c "import sys; sys.exit(0 if float('${BAL_AFTER}'.replace(',','') or 0) > float('${BAL_BEFORE}'.replace(',','') or 0) else 1)"; then
    break
  fi
  sleep 0.5
done

python3 -c "
import sys
before=float('${BAL_BEFORE}'.replace(',','') or 0)
after=float('${BAL_AFTER}'.replace(',','') or 0)
print(f'SIKA balance: {before} → {after}')
sys.exit(0 if after > before else 1)
" || { echo "FAIL: refund did not return SIKA"; exit 1; }

echo "=== verify-rex-unstake complete ==="
