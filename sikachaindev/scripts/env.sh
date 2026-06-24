#!/usr/bin/env bash
ENV_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${ENV_SH_DIR}/.." && pwd)"
BUILD_BIN="${ROOT}/../build/programs"
CHAIN_JSON="${ROOT}/chain.json"

export NODE_URL="${NODE_URL:-http://127.0.0.1:8888}"
export WALLET_URL="${WALLET_URL:-http://127.0.0.1:8899}"

if [[ -z "${CLEOS:-}" ]]; then
  if [[ -x "${BUILD_BIN}/cleos/cleos" ]]; then
    CLEOS="${BUILD_BIN}/cleos/cleos"
  else
    CLEOS="cleos"
  fi
fi

if [[ -z "${NODEOS:-}" ]]; then
  if [[ -x "${BUILD_BIN}/nodeos/nodeos" ]]; then
    NODEOS="${BUILD_BIN}/nodeos/nodeos"
  else
    NODEOS="nodeos"
  fi
fi

if [[ -z "${KEOSD:-}" ]]; then
  if [[ -x "${BUILD_BIN}/keosd/keosd" ]]; then
    KEOSD="${BUILD_BIN}/keosd/keosd"
  else
    KEOSD="keosd"
  fi
fi

cleos() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

# Unlock default keosd wallet (password in wallet/.password).
cleos_unlock() {
  cleos wallet open >/dev/null 2>&1 || true
  local pw_file="${ROOT}/wallet/.password"
  if [[ -f "${pw_file}" ]]; then
    cleos wallet unlock --password "$(tr -d '\n' < "${pw_file}")" >/dev/null 2>&1 || true
  fi
}

# Ensure keosd is up and dev keys are imported.
cleos_wallet_ready() {
  if ! curl -sf "${WALLET_URL}/v1/wallet/list_wallets" >/dev/null 2>&1; then
    echo "error: keosd not reachable at ${WALLET_URL} — run bash scripts/start-keosd.sh" >&2
    return 1
  fi
  bash "${ENV_SH_DIR}/setup-wallet.sh" >/dev/null
  cleos_unlock
}

# Privileged system account — matches config.hpp (sika / sika.null / sika.prods).
export SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT:-sika}"
export SIKACHAIN_DEV="${SIKACHAIN_DEV:-1}"
export SIKA_ACCOUNTS_JSON="${ROOT}/accounts.phase3.json"

export SIKA_APP_PORT="${SIKA_APP_PORT:-3003}"
export SIKA_APP_URL="${SIKA_APP_URL:-http://127.0.0.1:${SIKA_APP_PORT}}"
export SIKA_CHAIN_WEB_PORT="${SIKA_CHAIN_WEB_PORT:-3004}"
export SIKA_CHAIN_WEB_URL="${SIKA_CHAIN_WEB_URL:-http://127.0.0.1:${SIKA_CHAIN_WEB_PORT}}"
export SIKA_CHAIN_WEB_DIR="${SIKA_CHAIN_WEB_DIR:-/Users/randallroland/Desktop/Projects/SikaChain}"
export MSIG_ACCOUNT="${MSIG_ACCOUNT:-$(python3 -c "import json; print(json.load(open('${CHAIN_JSON}')).get('msigContract','sika.msig'))" 2>/dev/null || echo sika.msig)}"
export SIKA_TOKEN_ACCOUNT="${SIKA_TOKEN_ACCOUNT:-sika.token}"

# Unique msig proposal name (12-char eosio limit; chars a-z and 1-5 only).
msig_proposal_name() {
  local prefix="${1:-prop}"
  local suffix
  suffix="$(python3 -c "import secrets; chars='12345abcdefghijklmnopqrstuvwxyz'; n=12-len('${prefix}'); print(''.join(secrets.choice(chars) for _ in range(n)))")"
  printf '%s%s' "${prefix}" "${suffix}"
}

# Count nodeos processes under data/multinode/ (6-BP / 21-BP clusters).
multinode_node_count() {
  local n
  n="$(pgrep -fl "nodeos.*${ROOT}/data/multinode/" 2>/dev/null | wc -l | tr -d '[:space:]')"
  echo "${n:-0}"
}

# True when two or more multinode nodeos instances are running.
is_multinode_cluster() {
  [[ "$(multinode_node_count)" -ge 2 ]]
}

# Poll until msig proposal row is readable (multinode / async propose).
msig_wait_proposal() {
  local proposer="$1" prop="$2" msig="${3:-${MSIG_ACCOUNT}}" max="${4:-120}" i
  for ((i = 0; i < max; i++)); do
    if curl -sf "${NODE_URL}/v1/chain/get_table_rows" \
      -d "{\"json\":true,\"code\":\"${msig}\",\"scope\":\"${proposer}\",\"table\":\"proposal\",\"lower_bound\":\"${prop}\",\"upper_bound\":\"${prop}\",\"limit\":1}" \
      | python3 -c "import json,sys; sys.exit(0 if json.load(sys.stdin).get('rows') else 1)" 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  echo "FAIL: proposal ${prop} not visible after ${max} polls" >&2
  return 1
}

# Poll approvals2 after approve (multinode read lag).
msig_wait_approval() {
  local proposer="$1" prop="$2" msig="${3:-${MSIG_ACCOUNT}}" max="${4:-120}" i n
  for ((i = 0; i < max; i++)); do
    n=$(curl -sf "${NODE_URL}/v1/chain/get_table_rows" \
      -d "{\"json\":true,\"code\":\"${msig}\",\"scope\":\"${proposer}\",\"table\":\"approvals2\",\"lower_bound\":\"${prop}\",\"upper_bound\":\"${prop}\",\"limit\":1}" \
      | python3 -c "
import json, sys
rows = json.load(sys.stdin).get('rows', [])
print(len(rows[0].get('provided_approvals', [])) if rows else 0)
" 2>/dev/null || echo "0")
    if [[ "${n}" -ge 1 ]]; then
      return 0
    fi
    sleep 0.5
  done
  echo "FAIL: no approvals for ${prop} after ${max} polls" >&2
  return 1
}
