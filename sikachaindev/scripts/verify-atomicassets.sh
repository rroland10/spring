#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

AA_ACCOUNT="${ATOMICASSETS_ACCOUNT:-atomicassets}"

echo "=== verify-atomicassets (${AA_ACCOUNT}) ==="

curl -sf "${NODE_URL}/v1/chain/get_code" \
  -H 'Content-Type: application/json' \
  -d "{\"account_name\":\"${AA_ACCOUNT}\"}" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('wasm') else 1)" \
  || { echo "FAIL: ${AA_ACCOUNT} has no WASM — run deploy-atomicassets.sh" >&2; exit 1; }
echo "OK: contract deployed"

if "${CLEOS}" --url "${NODE_URL}" get table "${AA_ACCOUNT}" "${AA_ACCOUNT}" config 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('rows') else 1)"; then
  echo "OK: config table initialized"
else
  echo "FAIL: config table missing — push init on ${AA_ACCOUNT}" >&2
  exit 1
fi

echo "=== verify-atomicassets complete ==="
