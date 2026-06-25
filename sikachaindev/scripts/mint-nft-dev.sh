#!/usr/bin/env bash
# Mint a dev NFT to sikadev via AtomicAssets (collection + schema + asset).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

AA="${ATOMICASSETS_ACCOUNT:-atomicassets}"
OWNER="${NFT_OWNER:-sikadev}"
AUTHOR="${NFT_AUTHOR:-sikadev}"
COLLECTION="${NFT_COLLECTION:-sikadev}"
SCHEMA="${NFT_SCHEMA:-devschema}"

cleos_cmd() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

cleos_push() {
  cleos_cmd push "$@" -x 3600
}

push_or_skip() {
  local label="$1"
  shift
  local err
  if err="$("$@" 2>&1)"; then
    echo "OK: ${label}"
    return 0
  fi
  if echo "${err}" | grep -qiE 'already exists|duplicate|constraint|unchanged'; then
    echo "SKIP: ${label} (already present)"
    return 0
  fi
  echo "${err}" >&2
  return 1
}

PASSWORD_FILE="${ROOT}/wallet/.password"
if [[ -f "${PASSWORD_FILE}" ]]; then
  DEV_PW="$(tr -d '\n' < "${PASSWORD_FILE}")"
  cleos_cmd wallet open 2>/dev/null || true
  cleos_cmd wallet unlock --password "${DEV_PW}" 2>/dev/null || true
fi

bash "${SCRIPT_DIR}/verify-atomicassets.sh"

echo "=== AtomicAssets dev mint (${COLLECTION}/${SCHEMA} → ${OWNER}) ==="

push_or_skip "createcol ${COLLECTION}" \
  cleos_push action "${AA}" createcol \
  "[\"${AUTHOR}\",\"${COLLECTION}\",true,[\"${AUTHOR}\"],[],0,[]]" \
  -p "${AUTHOR}@active"

push_or_skip "createschema ${SCHEMA}" \
  cleos_push action "${AA}" createschema \
  "[\"${AUTHOR}\",\"${COLLECTION}\",\"${SCHEMA}\",[{\"name\":\"name\",\"type\":\"string\"}]]" \
  -p "${AUTHOR}@active"

push_or_skip "mintasset" \
  cleos_push action "${AA}" mintasset \
  "[\"${AUTHOR}\",\"${COLLECTION}\",\"${SCHEMA}\",-1,\"${OWNER}\",[],[[\"name\",[\"string\",\"Sika Dev #1\"]]],[]]" \
  -p "${AUTHOR}@active" -p "${AA}@active"

ASSET_ID=""
for _ in $(seq 1 30); do
  ASSET_ID=$(cleos_cmd get table "${AA}" "${OWNER}" assets -l 100 2>/dev/null | python3 -c "
import json,sys
rows=json.load(sys.stdin).get('rows',[])
print(rows[-1]['asset_id'] if rows else '')
" 2>/dev/null || true)
  if [[ -n "${ASSET_ID}" ]]; then
    break
  fi
  sleep 0.5
done

if [[ -n "${ASSET_ID}" ]]; then
  echo "OK: sikadev holds asset_id ${ASSET_ID}"
else
  echo "FAIL: no assets row for ${OWNER}" >&2
  exit 1
fi

echo "=== mint-nft-dev complete ==="
