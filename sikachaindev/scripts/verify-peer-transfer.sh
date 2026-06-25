#!/usr/bin/env bash
# On-chain peer transfer smoke: sikadev → sikauser1 (requires funded dev accounts).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

FROM="${PEER_FROM:-sikadev}"
TO="${PEER_TO:-sikauser1}"
SYMBOL="${PEER_SYMBOL:-SIKA}"
AMOUNT="${PEER_AMOUNT:-1.0000 ${SYMBOL}}"
TOKEN="${SIKA_TOKEN_ACCOUNT:-sika.token}"

echo "=== Peer transfer (${FROM} → ${TO}, ${AMOUNT}) ==="
bash "${SCRIPT_DIR}/setup-wallet.sh" >/dev/null

before="$(curl -sf "${NODE_URL}/v1/chain/get_currency_balance" \
  -H 'Content-Type: application/json' \
  -d "{\"code\":\"${TOKEN}\",\"account\":\"${TO}\",\"symbol\":\"${SYMBOL}\"}" \
  | python3 -c "import json,sys; b=json.load(sys.stdin); print(float(b[0].split()[0]) if b else 0)")"

"${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" transfer "${FROM}" "${TO}" "${AMOUNT}" \
  "SikaChainDev peer test" -c "${TOKEN}" -p "${FROM}@active" -x 3600

head_at_send=$(curl -sf "${NODE_URL}/v1/chain/get_info" | python3 -c "import json,sys; print(json.load(sys.stdin)['head_block_num'])")

read_balance() {
  curl -sf "${NODE_URL}/v1/chain/get_currency_balance" \
    -H 'Content-Type: application/json' \
    -d "{\"code\":\"${TOKEN}\",\"account\":\"${TO}\",\"symbol\":\"${SYMBOL}\"}" \
    | python3 -c "import json,sys; b=json.load(sys.stdin); print(float(b[0].split()[0]) if b else 0)" 2>/dev/null || echo "0"
}

after="${before}"
for _ in $(seq 1 120); do
  head_now=$(curl -sf "${NODE_URL}/v1/chain/get_info" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['head_block_num'])" 2>/dev/null || echo "0")
  after="$(read_balance)"
  if python3 -c "import sys; sys.exit(0 if ${after} >= ${before} + float('${AMOUNT}'.split()[0]) - 0.0001 else 1)"; then
    break
  fi
  # Fallback: cleos balance read can lag behind curl on busy multinode RPC.
  cleos_after="$("${CLEOS}" --url "${NODE_URL}" get currency balance "${TOKEN}" "${TO}" "${SYMBOL}" 2>/dev/null | awk '{print $1}' || echo "0")"
  if python3 -c "import sys; sys.exit(0 if float('${cleos_after}' or 0) >= ${before} + float('${AMOUNT}'.split()[0]) - 0.0001 else 1)"; then
    after="${cleos_after}"
    break
  fi
  if [[ "${head_now}" -gt "${head_at_send}" ]]; then
    after="$(read_balance)"
    if python3 -c "import sys; sys.exit(0 if ${after} >= ${before} + float('${AMOUNT}'.split()[0]) - 0.0001 else 1)"; then
      break
    fi
  fi
  sleep 0.5
done

python3 -c "
before, after, amt = ${before}, ${after}, float('${AMOUNT}'.split()[0])
sym = '${SYMBOL}'
if after >= before + amt - 0.0001:
    print(f'OK: ${TO} balance {before} → {after} {sym}')
else:
    raise SystemExit(f'FAIL: expected +{amt}, got {after - before}')
"

echo "=== verify-peer-transfer complete ==="
