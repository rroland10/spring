#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"

MSIG_ACCOUNT="${MSIG_ACCOUNT:-sika.msig}"

echo "=== SikaChainDev ==="
if curl -sf "${NODE_URL}/v1/chain/get_info" | python3 -c "
import json, sys
i = json.load(sys.stdin)
print(f\"  chain_id:     {i['chain_id']}\")
print(f\"  head_block:   {i['head_block_num']}\")
lib_gap = i['head_block_num'] - i['last_irreversible_block_num']
print(f\"  lib:          {i['last_irreversible_block_num']}  (gap {lib_gap})\")
if lib_gap > 5000:
    print(f\"  warning:      large head-lib gap — multinode may stall at 3600 without BP_MAX_REVERSIBLE_BLOCKS\")
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
import json, os
c = json.load(open('${ROOT}/chain.json'))
proto = os.environ.get('SIKA_PROTOCOL_ACCOUNT', c.get('protocolAccount', 'sikaio'))
sys_acct = os.environ.get('SIKA_SYSTEM_ACCOUNT', c.get('systemContract', 'sika'))
proto_key = c['accounts'].get(proto, {})
sys_key = c['accounts'].get(sys_acct, c['accounts'].get('sika', {}))
print(f\"  {proto:12} {proto_key.get('publicKey', 'n/a')}\")
print(f\"  {sys_acct:12} {sys_key.get('publicKey', 'n/a')}\")
for name, acct in sorted(c.get('accounts', {}).items()):
    if acct.get('privateKey') and name not in (proto, sys_acct):
        print(f\"  {name + ':':12} {acct.get('publicKey', 'n/a')}\")
" 2>/dev/null || true

  echo ""
  echo "=== Dev accounts ==="
  python3 -c "
import json, os, subprocess, sys
c = json.load(open('${ROOT}/chain.json'))
rpc = os.environ.get('NODE_URL', 'http://127.0.0.1:8888')
token = os.environ.get('SIKA_TOKEN_ACCOUNT', 'sika.token')
sys_acct = os.environ.get('SIKA_SYSTEM_ACCOUNT', c.get('systemContract', 'sika'))
names = [n for n, a in c.get('accounts', {}).items() if a.get('privateKey') and n not in ('sika',)]
if sys_acct not in names and sys_acct in c.get('accounts', {}):
    names.insert(0, sys_acct)
for name in names:
    try:
        r = subprocess.run(
            ['curl', '-sf', f'{rpc}/v1/chain/get_account',
             '-H', 'Content-Type: application/json',
             '-d', json.dumps({'account_name': name})],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode != 0 or 'account_name' not in r.stdout:
            print(f'  {name + \":\":12} (not created — run create-dev-accounts.sh)')
            continue
        bal = subprocess.run(
            ['curl', '-sf', f'{rpc}/v1/chain/get_currency_balance',
             '-H', 'Content-Type: application/json',
             '-d', json.dumps({'code': token, 'account': name, 'symbol': 'SIKA'})],
            capture_output=True, text=True, timeout=5,
        )
        bal_arr = json.loads(bal.stdout) if bal.stdout.strip() else []
        sika = bal_arr[0] if bal_arr else '(0 SIKA)'
        cghs_r = subprocess.run(
            ['curl', '-sf', f'{rpc}/v1/chain/get_currency_balance',
             '-H', 'Content-Type: application/json',
             '-d', json.dumps({'code': token, 'account': name, 'symbol': 'CGHS'})],
            capture_output=True, text=True, timeout=5,
        )
        cghs_arr = json.loads(cghs_r.stdout) if cghs_r.stdout.strip() else []
        cghs = cghs_arr[0] if cghs_arr else ''
        if name == sys_acct and not bal_arr and not cghs_arr:
            acct = json.loads(r.stdout)
            label = 'privileged system' if acct.get('privileged') else sika
            print(f'  {name + \":\":12} {label}')
            continue
        extra = f'  {cghs}' if cghs else ''
        print(f'  {name + \":\":12} {sika}{extra}')
    except Exception:
        print(f'  {name + \":\":12} (query failed)')
" 2>/dev/null || true

  echo "=== Multisig (${MSIG_ACCOUNT}) ==="
  if curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${MSIG_ACCOUNT}\"}" >/dev/null 2>&1; then
    MSIG_PRIV=$(curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${MSIG_ACCOUNT}\"}" \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('privileged', False))" 2>/dev/null || echo "False")
    echo "  deployed:     yes"
    echo "  privileged:   ${MSIG_PRIV}"
  else
    echo "  deployed:     no (run deploy-msig.sh)"
  fi

  LEGACY_MSIG="eosio.msig"
  if [[ "${LEGACY_MSIG}" != "${MSIG_ACCOUNT}" ]] \
    && curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${LEGACY_MSIG}\"}" >/dev/null 2>&1; then
    LEG_PRIV=$(curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${LEGACY_MSIG}\"}" \
      | python3 -c "import json,sys; print(json.load(sys.stdin).get('privileged', False))" 2>/dev/null || echo "False")
    LEG_CODE=$(curl -sf "${NODE_URL}/v1/chain/get_code" -d "{\"account_name\":\"${LEGACY_MSIG}\"}" \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d.get('wasm') else 'no')" 2>/dev/null || echo "?")
    if [[ "${LEG_PRIV}" == "True" ]] || [[ "${LEG_CODE}" == "yes" ]]; then
      echo "  legacy ${LEGACY_MSIG}: privileged=${LEG_PRIV} code=${LEG_CODE} — run cleanup-legacy-msig.sh"
    else
      echo "  legacy ${LEGACY_MSIG}: retired"
    fi
  fi

  AA="${ATOMICASSETS_ACCOUNT:-atomicassets}"
  echo "=== NFTs (${AA}) ==="
  if curl -sf "${NODE_URL}/v1/chain/get_code" -d "{\"account_name\":\"${AA}\"}" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d.get('wasm') else 'no')" 2>/dev/null | grep -q yes; then
    NFT_COUNT=$(curl -sf "${NODE_URL}/v1/chain/get_table_rows" \
      -H 'Content-Type: application/json' \
      -d "{\"json\":true,\"code\":\"${AA}\",\"scope\":\"sikadev\",\"table\":\"assets\",\"limit\":1}" \
      2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('rows',[])))" 2>/dev/null || echo "0")
    echo "  deployed:     yes"
    echo "  sikadev NFTs: ${NFT_COUNT}+ (run mint-nft-dev.sh)"
  else
    echo "  deployed:     no (run deploy-atomicassets.sh)"
  fi

  HYPERION_URL=$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json')).get('hyperionUrl','') or '')" 2>/dev/null)
  echo "=== Indexer ==="
  if [[ -n "${HYPERION_URL}" ]]; then
    echo "  hyperionUrl:  ${HYPERION_URL}"
    curl -sf "${HYPERION_URL%/}/v2/health" >/dev/null 2>&1 && echo "  health:       ok" || echo "  health:       unreachable"
  else
    echo "  hyperion:     not configured (see docs/hyperion-dev.md)"
  fi
  if curl -sf http://127.0.0.1:8080 >/dev/null 2>&1 || nc -z 127.0.0.1 8080 2>/dev/null; then
    echo "  SHIP:         listening :8080"
  else
    echo "  SHIP:         off (ENABLE_SHIP=1 start-all.sh)"
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
MN="$(multinode_node_count 2>/dev/null || echo 0)"
if [[ "${MN}" -ge 2 ]]; then
  echo "  nodeos: running (${MN} multinode instances)"
elif pgrep -fl "nodeos.*${ROOT}/data" >/dev/null; then
  echo "  nodeos: running (single-node)"
else
  echo "  nodeos: stopped"
fi
pgrep -fl "keosd.*${ROOT}/wallet" >/dev/null && echo "  keosd:  running" || echo "  keosd:  stopped"
