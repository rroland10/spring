#!/usr/bin/env bash
# Build and deploy AtomicAssets (pink.network NFT standard) on SikaChainDev.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

AA_ACCOUNT="${ATOMICASSETS_ACCOUNT:-atomicassets}"
AA_REPO="${AA_REPO:-https://github.com/pinknetworkx/atomicassets-contract.git}"
AA_SRC="${ROOT}/.atomicassets-src"
BUILD_OUT="${ROOT}/.atomicassets-build"
PUB="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['publicKey'])")"
SIKA_SYSTEM="${SIKA_SYSTEM_ACCOUNT:-sika}"
SIKA_TOKEN="${SIKA_TOKEN_ACCOUNT:-sika.token}"

retry() { local n=0; until "$@" || [[ $((n+=1)) -ge 5 ]]; do sleep 1; done; }

cleos_cmd() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

push_action_or_skip() {
  local label="$1"
  shift
  local err
  if err="$("$@" 2>&1)"; then
    return 0
  fi
  if echo "${err}" | grep -qiE 'already|duplicate|constraint|unchanged|initialized'; then
    echo "  (skip) ${label}"
    return 0
  fi
  echo "${err}" >&2
  return 1
}

ensure_contract_ram() {
  local acct="$1"
  local min_quota="${2:-2500000}"
  local quota usage need_buy guard_sika top_up
  read -r quota usage <<<"$(cleos_cmd get account "${acct}" -j 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d['ram_quota'], d['ram_usage'])
" 2>/dev/null || echo "0 0")"
  if [[ "${quota}" -lt "${min_quota}" ]]; then
    need_buy=$(( min_quota - quota + 131072 ))
    echo "  buying RAM for ${acct} (quota ${quota} → ${min_quota}, +${need_buy} bytes)..."
    guard_sika="$(cleos_cmd get currency balance "${SIKA_TOKEN}" sika.guard SIKA 2>/dev/null | awk '{print $1}' | tr -d ',' || echo "0")"
    top_up=$(( need_buy / 1024 * 20 + 5000 ))
    if ! python3 -c "import sys; sys.exit(0 if float('${guard_sika:-0}') >= ${top_up} else 1)" 2>/dev/null; then
      cleos_cmd push action "${SIKA_TOKEN}" transfer \
        "[\"${SIKA_SYSTEM}\",\"sika.guard\",\"${top_up}.0000 SIKA\",\"RAM purchase fund\"]" \
        -p "${SIKA_SYSTEM}@active" >/dev/null
    fi
    retry cleos_cmd push action "${SIKA_SYSTEM}" buyrambytes \
      "[\"sika.guard\",\"${acct}\",${need_buy}]" -p sika.guard@active
  fi
}

echo "=== AtomicAssets source (${AA_SRC}) ==="
if [[ ! -f "${AA_SRC}/src/atomicassets.cpp" ]]; then
  rm -rf "${AA_SRC}"
  git clone --depth 1 "${AA_REPO}" "${AA_SRC}"
fi

echo "=== Build ${AA_ACCOUNT} WASM ==="
rm -rf "${BUILD_OUT}"
mkdir -p "${BUILD_OUT}"

docker run --rm --platform linux/amd64 \
  -v "${AA_SRC}:/src:ro" \
  -v "${BUILD_OUT}:/out" \
  ubuntu:22.04 bash -c '
    set -e
    apt-get update -qq && apt-get install -qq -y wget > /dev/null
    if ! command -v cdt-cpp >/dev/null 2>&1; then
      wget -q https://github.com/AntelopeIO/cdt/releases/download/v4.1.1/cdt_4.1.1-1_amd64.deb -O /tmp/cdt.deb
      apt-get install -qq -y /tmp/cdt.deb > /dev/null
    fi
    export PATH=/usr/bin:$PATH
    cdt-cpp -abigen -contract atomicassets -R /src/resource \
      -I/usr/include/eosio -I/usr/include/eosio/system \
      -I/usr/include/eosio/libc++ -I/usr/include/eosio/libc++abi -I/src/include \
      -o /out/atomicassets.wasm /src/src/atomicassets.cpp
    mv /out/atomic.abi /out/atomicassets.abi 2>/dev/null || true
  '

if [[ -f "${BUILD_OUT}/atomicassets" ]] && [[ ! -f "${BUILD_OUT}/atomicassets.wasm" ]]; then
  mv "${BUILD_OUT}/atomicassets" "${BUILD_OUT}/atomicassets.wasm"
fi

DEPLOY_DIR="${BUILD_OUT}/${AA_ACCOUNT}"
mkdir -p "${DEPLOY_DIR}"
cp "${BUILD_OUT}/atomicassets.wasm" "${DEPLOY_DIR}/${AA_ACCOUNT}.wasm"
cp "${BUILD_OUT}/atomicassets.abi" "${DEPLOY_DIR}/${AA_ACCOUNT}.abi"

if [[ ! -f "${BUILD_OUT}/atomicassets.wasm" ]]; then
  echo "error: atomicassets build failed"
  exit 1
fi

PASSWORD_FILE="${ROOT}/wallet/.password"
if [[ -f "${PASSWORD_FILE}" ]]; then
  DEV_PW="$(tr -d '\n' < "${PASSWORD_FILE}")"
  cleos_cmd wallet open 2>/dev/null || true
  cleos_cmd wallet unlock --password "${DEV_PW}" 2>/dev/null || true
fi

echo "=== Deploy ${AA_ACCOUNT} ==="
if ! curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${AA_ACCOUNT}\"}" >/dev/null 2>&1; then
  echo "Creating account ${AA_ACCOUNT}..."
  RAM_BYTES=65536 bash "${SCRIPT_DIR}/create-account.sh" "${AA_ACCOUNT}" "${PUB}"
fi

ensure_contract_ram "${AA_ACCOUNT}" 2500000
retry cleos_cmd set contract "${AA_ACCOUNT}" "${DEPLOY_DIR}/"

retry cleos_cmd set account permission \
  "${AA_ACCOUNT}" active --add-code -p "${AA_ACCOUNT}@active"

echo "=== Initialize AtomicAssets ==="
retry cleos_cmd push action "${AA_ACCOUNT}" init '[]' -p "${AA_ACCOUNT}@active"

if [[ "${VERIFY_ATOMICASSETS:-1}" == "1" ]]; then
  bash "${SCRIPT_DIR}/verify-atomicassets.sh" || echo "  (verify-atomicassets failed)"
fi

echo "=== ${AA_ACCOUNT} ready ==="
