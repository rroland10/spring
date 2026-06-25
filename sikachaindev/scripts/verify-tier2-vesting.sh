#!/usr/bin/env bash
# Enable Tier-2 vesting on dev and smoke-test claimprod → claimvest → REX.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

SIKA_SYSTEM="${SIKA_SYSTEM_ACCOUNT:-sika}"
PRODUCER="${SETTLEMENT_TEST_BP:-sikabpa}"
VEST_SECONDS="${SIKA_VEST_SECONDS:-31536000}"

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

echo "=== 1. Enable Tier-2 vesting (${VEST_SECONDS}s vest, 80% usage gate) ==="
cleos_push "${SIKA_SYSTEM}" setvesting \
  "[\"${SIKA_SYSTEM}\",1,${VEST_SECONDS},8000]" -p "${SIKA_SYSTEM}@active"

echo "=== 2. Accrue epoch fee revenue (usage gate fuel) ==="
bash "${SCRIPT_DIR}/settlement-sweep.sh" gh "5000.0000 CGHS"

echo "=== 3. Refill inflation pay buckets ==="
cleos_push "${SIKA_SYSTEM}" refillpay "[\"${SIKA_SYSTEM}\"]" -p "${SIKA_SYSTEM}@active"

echo "=== 3b. Recompute vote weights (refresh global total) ==="
# Re-vote from first staked BP to trigger update_votes → recompute_producer_vote_weight
VOTER="${SIKA_VOTE_REFRESH:-sikabpa}"
PRODS=(sikabpa sikabpb sikabpc sikabpd sikabpe sikabpf sikabpg sikabph sikabpi sikabpj
       sikabpk sikabpl sikabpm sikabpn sikabpo sikabpp sikabpq sikabpr sikabps sikabpt sikabpu)
cleos_cmd system voteproducer prods "${VOTER}" "${PRODS[@]}" -p "${VOTER}@active" 2>/dev/null || true

cleos_cmd get table "${SIKA_SYSTEM}" "${SIKA_SYSTEM}" global 2>/dev/null | python3 -c "
import json,sys
r=json.load(sys.stdin)['rows'][0]
print('  perblock_bucket', r.get('perblock_bucket'))
print('  pervote_bucket', r.get('pervote_bucket'))
print('  total_producer_vote_weight', r.get('total_producer_vote_weight'))
" || true

echo "=== 4. claimprod (Tier-1 CUSD + Tier-2 vest escrow) ==="
CLAIMED=0
for bp in sikabpa sikabpb sikabpc sikabpd sikabpe sikabpf sikabpg sikabph sikabpi sikabpj \
          sikabpk sikabpl sikabpm sikabpn sikabpo sikabpp sikabpq sikabpr sikabps sikabpt sikabpu; do
  if cleos_push "${SIKA_SYSTEM}" claimprod "[\"${bp}\"]" -p "${bp}@active" 2>/dev/null; then
    PRODUCER="${bp}"
    CLAIMED=1
    echo "claimed as ${bp}"
    break
  fi
done
if [[ "${CLAIMED}" -eq 0 ]]; then
  PRODUCER=$(cleos_cmd get table "${SIKA_SYSTEM}" "${SIKA_SYSTEM}" bpvest -l 100 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin).get('rows',[])
for r in rows:
  if not r.get('forfeited') and r.get('released_amount',0) < r.get('total_amount',0):
    print(r['owner'])
    break
" || true)
  if [[ -n "${PRODUCER:-}" ]]; then
    CLAIMED=1
    echo "resume: existing bpvest for ${PRODUCER}"
  else
    echo "FAIL: no BP available (24h claim cooldown on all producers)" >&2
    exit 1
  fi
fi

echo "=== 5. BP vest row ==="
VEST_JSON='{"rows":[]}'
read_bpvest_row() {
  local owner="$1"
  cleos_cmd get table "${SIKA_SYSTEM}" "${SIKA_SYSTEM}" bpvest \
    -L "${owner}" -U "${owner}" 2>/dev/null \
    || cleos_cmd get table "${SIKA_SYSTEM}" "${SIKA_SYSTEM}" bpvest -l 500 2>/dev/null \
    | python3 -c "
import json,sys
owner='${owner}'
for r in json.load(sys.stdin).get('rows',[]):
  if r.get('owner')==owner:
    print(json.dumps({'rows':[r]}))
    break
else:
  print('{\"rows\":[]}')
"
}
for _ in $(seq 1 120); do
  VEST_JSON="$(read_bpvest_row "${PRODUCER}")"
  if echo "${VEST_JSON}" | grep -q '"total_amount"'; then
    break
  fi
  sleep 0.5
done
echo "${VEST_JSON}"
if ! echo "${VEST_JSON}" | grep -q '"total_amount"'; then
  echo "FAIL: no bpvest row — Tier-2 pay was zero (check buckets / usage gate)" >&2
  exit 1
fi

echo "=== 6. claimvest (auto-REX from escrow) ==="
if [[ "${VEST_SECONDS}" -le 120 ]]; then
  echo "Short vest (${VEST_SECONDS}s) — waiting $(( VEST_SECONDS + 1 ))s..."
  sleep $(( VEST_SECONDS + 1 ))
  cleos_push "${SIKA_SYSTEM}" claimvest "[\"${PRODUCER}\"]" -p "${PRODUCER}@active"
else
  echo "Long vest (${VEST_SECONDS}s) — claimvest may release 0 immediately (expected)."
  cleos_push "${SIKA_SYSTEM}" claimvest "[\"${PRODUCER}\"]" -p "${PRODUCER}@active" || true
  echo "For full release test: SIKA_VEST_SECONDS=60 bash verify-tier2-vesting.sh (fresh BP required)"
fi

echo "=== 7. REX balance for ${PRODUCER} ==="
cleos_cmd get table "${SIKA_SYSTEM}" "${SIKA_SYSTEM}" rexbal -l 100 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin).get('rows',[])
for r in rows:
  if r.get('owner')=='${PRODUCER}':
    print(json.dumps(r, indent=2))
    break
else:
  print('(no rexbal row yet)')
" || true

echo "=== verify-tier2-vesting complete ==="
