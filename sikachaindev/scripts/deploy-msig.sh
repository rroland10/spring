#!/usr/bin/env bash
# Build and deploy sika.msig (standard multisig WASM) on SikaChainDev.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

MSIG_ACCOUNT="${MSIG_ACCOUNT:-sika.msig}"
MSIG_SRC="${ROOT}/../unittests/contracts/eosio.msig"
BUILD_OUT="${ROOT}/.msig-build/${MSIG_ACCOUNT}"
PUB="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['publicKey'])")"
SIKA_SYSTEM="${SIKA_SYSTEM_ACCOUNT:-sika}"
SIKA_TOKEN="${SIKA_TOKEN_ACCOUNT:-sika.token}"

retry() { local n=0; until "$@" || [[ $((n+=1)) -ge 5 ]]; do sleep 1; done; }

push_action_or_skip() {
  local label="$1"
  shift
  local err
  if err="$("$@" 2>&1)"; then
    return 0
  fi
  if echo "${err}" | grep -qiE 'already|duplicate|constraint|unchanged'; then
    echo "  (skip) ${label}"
    return 0
  fi
  echo "${err}" >&2
  return 1
}

cleos_cmd() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

ensure_contract_ram() {
  local acct="$1"
  local min_quota="${2:-300000}"
  local quota usage need_buy guard_sika top_up
  read -r quota usage <<<"$(cleos_cmd get account "${acct}" -j 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d['ram_quota'], d['ram_usage'])
" 2>/dev/null || echo "0 0")"
  if [[ "${quota}" -lt "${min_quota}" ]]; then
    need_buy=$(( min_quota - quota + 65536 ))
    echo "  buying RAM for ${acct} (quota ${quota} → target ${min_quota}, +${need_buy} bytes)..."
    guard_sika="$(cleos_cmd get currency balance "${SIKA_TOKEN}" sika.guard SIKA 2>/dev/null | awk '{print $1}' | tr -d ',' || echo "0")"
    top_up=$(( need_buy / 1024 * 20 + 2000 ))
    if python3 -c "import sys; sys.exit(0 if float('${guard_sika:-0}') >= ${top_up} else 1)" 2>/dev/null; then
      :
    else
      echo "  topping up sika.guard with ${top_up}.0000 SIKA for RAM purchase..."
      cleos_cmd push action "${SIKA_TOKEN}" transfer \
        "[\"${SIKA_SYSTEM}\",\"sika.guard\",\"${top_up}.0000 SIKA\",\"RAM purchase fund\"]" \
        -p "${SIKA_SYSTEM}@active" >/dev/null
    fi
    retry cleos_cmd push action "${SIKA_SYSTEM}" buyrambytes \
      "[\"sika.guard\",\"${acct}\",${need_buy}]" -p sika.guard@active
  fi
}

echo "=== Build multisig WASM (${MSIG_ACCOUNT}) ==="
rm -rf "${BUILD_OUT}"
mkdir -p "${BUILD_OUT}"

docker run --rm --platform linux/amd64 \
  -v "${MSIG_SRC}:/src:ro" \
  -v "${BUILD_OUT}:/out" \
  ubuntu:22.04 bash -c '
    set -e
    apt-get update -qq && apt-get install -qq -y wget cmake > /dev/null
    if ! command -v cdt-cpp >/dev/null 2>&1; then
      wget -q https://github.com/AntelopeIO/cdt/releases/download/v4.1.1/cdt_4.1.1-1_amd64.deb -O /tmp/cdt.deb
      apt-get install -qq -y /tmp/cdt.deb > /dev/null
    fi
    export PATH=/usr/bin:$PATH
    cdt-cpp -abigen -contract eosio.msig -R /src/ricardian \
      -I/usr/include/eosio -I/usr/include/eosio/system \
      -I/usr/include/eosio/libc++ -I/usr/include/eosio/libc++abi -I/src \
      -o /out/eosio.msig /src/eosio.msig.cpp
    mv /out/eosio.abi /out/eosio.msig.abi
    mv /out/eosio.msig /out/eosio.msig.wasm
  '

mv "${BUILD_OUT}/eosio.msig.wasm" "${BUILD_OUT}/${MSIG_ACCOUNT}.wasm"
mv "${BUILD_OUT}/eosio.msig.abi" "${BUILD_OUT}/${MSIG_ACCOUNT}.abi"

if [[ ! -f "${BUILD_OUT}/${MSIG_ACCOUNT}.wasm" ]]; then
  echo "error: ${MSIG_ACCOUNT} build failed"
  exit 1
fi

PASSWORD_FILE="${ROOT}/wallet/.password"
if [[ -f "${PASSWORD_FILE}" ]]; then
  DEV_PW="$(tr -d '\n' < "${PASSWORD_FILE}")"
  cleos_cmd wallet open 2>/dev/null || true
  cleos_cmd wallet unlock --password "${DEV_PW}" 2>/dev/null || true
fi

echo "=== Deploy ${MSIG_ACCOUNT} ==="
if ! cleos_cmd get account "${MSIG_ACCOUNT}" -j >/dev/null 2>&1 \
  && ! curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${MSIG_ACCOUNT}\"}" >/dev/null 2>&1; then
  echo "Creating account ${MSIG_ACCOUNT}..."
  RAM_BYTES=65536 bash "${SCRIPT_DIR}/create-account.sh" "${MSIG_ACCOUNT}" "${PUB}"
fi

ensure_contract_ram "${MSIG_ACCOUNT}" 300000

retry cleos_cmd set contract "${MSIG_ACCOUNT}" "${BUILD_OUT}/"

retry cleos_cmd set account permission \
  "${MSIG_ACCOUNT}" active --add-code -p "${MSIG_ACCOUNT}@active"

# Privileged msig (EOS mainnet pattern) — allows exec to dispatch nested actions.
SIKA_RULES="${SIKA_RULES_ACCOUNT:-sika.rules}"
echo "=== Mark ${MSIG_ACCOUNT} privileged (setpriv) ==="
push_action_or_skip "${MSIG_ACCOUNT} setpriv" \
  cleos_cmd push action "${SIKA_SYSTEM}" setpriv "[\"${MSIG_ACCOUNT}\",1]" -p "${SIKA_RULES}@active" -f

if [[ "${VERIFY_MSIG:-1}" == "1" ]]; then
  bash "${SCRIPT_DIR}/verify-msig.sh" || echo "  (verify-msig failed — see verify-msig.sh)"
fi

if [[ "${CLEANUP_LEGACY_MSIG:-1}" == "1" ]] && [[ "${MSIG_ACCOUNT}" != "eosio.msig" ]]; then
  bash "${SCRIPT_DIR}/cleanup-legacy-msig.sh" || echo "  (cleanup-legacy-msig skipped — see cleanup-legacy-msig.sh)"
fi

echo "=== ${MSIG_ACCOUNT} ready ==="
cleos_cmd get account "${MSIG_ACCOUNT}" -j 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['account_name'], 'RAM', d['ram_quota'], 'privileged', d.get('privileged'))" \
  || cleos_cmd get account "${MSIG_ACCOUNT}" 2>&1 | head -15
