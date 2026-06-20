#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo "=== SikaChainDev ==="
if curl -sf "${NODE_URL}/v1/chain/get_info" | python3 -c "
import json, sys
i = json.load(sys.stdin)
print(f\"  chain_id:     {i['chain_id']}\")
print(f\"  head_block:   {i['head_block_num']}\")
print(f\"  lib:          {i['last_irreversible_block_num']}\")
print(f\"  producer:     {i['head_block_producer']}\")
print(f\"  version:      {i['server_full_version_string']}\")
" 2>/dev/null; then
  echo ""
  echo "=== Token (sika.token) ==="
  if "${CLEOS}" --url "${NODE_URL}" get currency stats sika.token SIKA 2>/dev/null | python3 -c "
import json, sys
s = json.load(sys.stdin).get('SIKA', {})
print(f\"  supply:       {s.get('supply', 'n/a')}\")
print(f\"  max_supply:   {s.get('max_supply', 'n/a')}\")
print(f\"  issuer:       {s.get('issuer', 'n/a')}\")
" 2>/dev/null; then
    :
  else
    echo "  (sika.token not deployed — run deploy-sika-system.sh)"
  fi

  echo "=== Dev keys (from chain.json) ==="
  python3 -c "
import json
c = json.load(open('${ROOT}/chain.json'))
print(f\"  eosio:        {c['accounts']['eosio']['publicKey']}\")
if 'sikadev' in c['accounts']:
    print(f\"  sikadev:      {c['accounts']['sikadev']['publicKey']}\")
" 2>/dev/null || true

  echo ""
  echo "=== Dev accounts ==="
  if curl -sf "${NODE_URL}/v1/chain/get_account" \
    -H 'Content-Type: application/json' \
    -d '{"account_name":"sikadev"}' | grep -q '"account_name"'; then
    BAL=$("${CLEOS}" --url "${NODE_URL}" get currency balance sika.token sikadev SIKA 2>/dev/null | tr -d '\n' || true)
    if [[ -n "${BAL}" ]]; then
      echo "  sikadev:      ${BAL}"
    else
      echo "  sikadev:      (exists, 0 SIKA)"
    fi
  else
    echo "  sikadev:      (not created — run create-account.sh)"
  fi
  if "${CLEOS}" --url "${NODE_URL}" get currency balance sika.token eosio SIKA >/dev/null 2>&1; then
    "${CLEOS}" --url "${NODE_URL}" get currency balance sika.token eosio SIKA 2>/dev/null | sed 's/^/  eosio:        /'
  fi
else
  echo "  nodeos not reachable at ${NODE_URL}"
  echo "  start: scripts/start-all.sh"
fi

echo ""
echo "=== Wallet ==="
curl -sf "${WALLET_URL}/v1/wallet/list_wallets" | python3 -m json.tool 2>/dev/null || echo "  (keosd not reachable — start-all.sh starts it)"

echo ""
echo "=== Processes ==="
pgrep -fl "nodeos.*${ROOT}/data" >/dev/null && echo "  nodeos: running" || echo "  nodeos: stopped"
pgrep -fl "keosd.*${ROOT}/wallet" >/dev/null && echo "  keosd:  running" || echo "  keosd:  stopped"
