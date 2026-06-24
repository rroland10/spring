#!/usr/bin/env bash
# Deploy SikaChain system contracts to SikaChainDev (local Spring node).
#
# Account layout (see ../accounts.json):
#   sika        — privileged Spring account (Phase 3); hosts sika.system WASM
#   sika.token  — SIKA + cGHS token contract
#   sika.rex    — REX pool custody
#   sika.*      — governance / issuer satellite contracts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

CONTRACTS_DIR="${SIKA_CONTRACTS_DIR:-/Users/randallroland/Desktop/Projects/sikachain sys contract/contracts}"
BUILD_DIR="${CONTRACTS_DIR}/build/contracts"
CORE_CONTRACTS_DIR="${CORE_CONTRACTS_DIR:-${ROOT}/../.system-contracts/contracts/build}"
EOSIO_BOOT_FALLBACK="${ROOT}/../unittests/contracts/eosio.boot"
HTTP_PORT=8888
PUB="$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['publicKey'])")"

SIKA_SYSTEM="${SIKA_SYSTEM_ACCOUNT:-sika}"
SIKA_TOKEN="${SIKA_TOKEN_ACCOUNT:-sika.token}"
SIKA_REX="${SIKA_REX_ACCOUNT:-sika.rex}"

retry() { local n=0; until "$@" || [[ $((n+=1)) -ge 5 ]]; do sleep 1; done; }

account_exists() {
  curl -sf "${NODE_URL}/v1/chain/get_account" \
    -H 'Content-Type: application/json' \
    -d "{\"account_name\":\"$1\"}" | grep -q '"account_name"'
}

wait_for_account() {
  local acct="$1"
  if account_exists "${acct}"; then
    return 0
  fi
  for _ in $(seq 1 120); do
    if account_exists "${acct}"; then
      return 0
    fi
    sleep 0.5
  done
  echo "error: account ${acct} not on chain after create" >&2
  return 1
}

wait_for_node() {
  local n=0
  until curl -sf "http://127.0.0.1:${HTTP_PORT}/v1/chain/get_info" >/dev/null 2>&1; do
    n=$((n + 1))
    if [[ $n -ge 60 ]]; then
      echo "error: nodeos not responding on port ${HTTP_PORT}"
      exit 1
    fi
    sleep 1
  done
}

token_already_deployed() {
  cleos_cmd get currency stats "${SIKA_TOKEN}" SIKA 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); s=d.get('SIKA',{}).get('supply','0').split()[0]; sys.exit(0 if float(s)>0 else 1)" 2>/dev/null
}

sika_token_created() {
  cleos_cmd get currency stats "${SIKA_TOKEN}" SIKA 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('SIKA',{}).get('max_supply') else 1)" 2>/dev/null
}

cghs_token_created() {
  cleos_cmd get currency stats "${SIKA_TOKEN}" CGHS 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('CGHS',{}).get('max_supply') else 1)" 2>/dev/null
}

cusd_token_created() {
  cleos_cmd get currency stats "${SIKA_TOKEN}" CUSD 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('CUSD',{}).get('max_supply') else 1)" 2>/dev/null
}

SIKA_ISSUER="${SIKA_ISSUE_ACCOUNT:-sika.issue}"
SIKA_USD_ISSUER="${SIKA_USD_ISSUER:-sika.usd}"
TREAS_BOOTSTRAP_CUSD="${TREAS_BOOTSTRAP_CUSD:-50000.0000 CUSD}"
TREAS_BOOTSTRAP_CGHS="${TREAS_BOOTSTRAP_CGHS:-100000.0000 CGHS}"
TREAS_COST_RECOVERY="${TREAS_COST_RECOVERY:-250.0000 CUSD}"

push_action_or_skip() {
  local label="$1"
  shift
  local err
  if err="$("$@" 2>&1)"; then
    return 0
  fi
  if echo "${err}" | grep -qiE 'already exists|already activated|already initialized|duplicate|constraint'; then
    echo "  (skip) ${label}"
    return 0
  fi
  echo "${err}" >&2
  return 1
}

cleos_cmd() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

# push_transaction (blocks until accepted; send_transaction2 returns early on Spring cleos).
cleos_tx() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" \
    "$@" --return-failure-trace false --use-old-rpc
}

ensure_settlement_account() {
  local acct="$1"
  local ram_bytes="${2:-4096}"
  if cleos_cmd get account "${acct}" >/dev/null 2>&1; then
    echo "  (exists) ${acct}"
    return 0
  fi
  RAM_BYTES="${ram_bytes}" bash "${SCRIPT_DIR}/create-account.sh" "${acct}" "${PUB}"
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
    # eosio cannot be RAM payer (buyram transfers SIKA payer → eosio contract).
    guard_sika="$(cleos_cmd get currency balance "${SIKA_TOKEN}" sika.guard SIKA 2>/dev/null | awk '{print $1}' | tr -d ',' || echo "0")"
    top_up=$(( need_buy / 1024 * 20 + 2000 ))
    if python3 -c "import sys; sys.exit(0 if float('${guard_sika:-0}') >= ${top_up} else 1)" 2>/dev/null; then
      :
    else
      echo "  topping up sika.guard with ${top_up}.0000 SIKA for RAM purchase..."
      cleos_tx push action "${SIKA_TOKEN}" transfer \
        "[\"${SIKA_SYSTEM}\",\"sika.guard\",\"${top_up}.0000 SIKA\",\"RAM purchase fund\"]" \
        -p "${SIKA_SYSTEM}@active" -x 3600 >/dev/null
    fi
    retry cleos_tx push action "${SIKA_SYSTEM}" buyrambytes \
      "[\"sika.guard\",\"${acct}\",${need_buy}]" -p sika.guard@active -x 3600
  fi
}

deploy_satellite_contract() {
  local acct="$1"
  local min_ram="${2:-0}"
  if [[ "${min_ram}" -gt 0 ]]; then
    ensure_contract_ram "${acct}" "${min_ram}"
  fi
  retry cleos_tx set contract "${acct}" "${BUILD_DIR}/${acct}/" -x 3600
}

ensure_treas_add_code() {
  push_action_or_skip "sika.treas active --add-code" \
    cleos_tx set account permission sika.treas active --add-code -p sika.treas@active -x 3600
}

bootstrap_treas_settlement() {
  if ! cusd_token_created; then
    echo "Creating CUSD reference token..."
    retry cleos_tx push action "${SIKA_TOKEN}" create \
      "[\"${SIKA_USD_ISSUER}\",\"10000000000.0000 CUSD\"]" -p "${SIKA_TOKEN}@active" -x 3600
  fi

  push_action_or_skip "sika.treas init" \
    cleos_tx push action sika.treas init "[]" -p "${SIKA_SYSTEM}@active" -x 3600

  push_action_or_skip "sika.treas setparams" \
    cleos_tx push action sika.treas setparams \
    "[\"${SIKA_SYSTEM}\",2500,\"${TREAS_COST_RECOVERY}\",500,2500,3000]" \
    -p "${SIKA_SYSTEM}@active" -x 3600

  if cusd_token_created; then
    TREAS_CUSD=$("${CLEOS}" --url "${NODE_URL}" get currency balance sika.token sika.treas CUSD 2>/dev/null | awk '{print $1}' || true)
    if [[ -z "${TREAS_CUSD}" ]]; then
      echo "Funding sika.treas BP bootstrap reserve (${TREAS_BOOTSTRAP_CUSD})..."
      retry cleos_tx push action "${SIKA_TOKEN}" issue \
        "[\"sika.treas\",\"${TREAS_BOOTSTRAP_CUSD}\",\"SikaChainDev BP bootstrap reserve\"]" \
        -p "${SIKA_USD_ISSUER}@active" -x 3600
      push_action_or_skip "sika.treas creditreserve" \
        cleos_tx push action sika.treas creditreserve "[\"${TREAS_BOOTSTRAP_CUSD}\"]" \
        -p "${SIKA_SYSTEM}@active" -x 3600
    fi
  fi

  if cghs_token_created; then
    TREAS_CGHS=$("${CLEOS}" --url "${NODE_URL}" get currency balance sika.token sika.treas CGHS 2>/dev/null | awk '{print $1}' || true)
    if [[ -z "${TREAS_CGHS}" ]]; then
      echo "Funding sika.treas REX yield float (${TREAS_BOOTSTRAP_CGHS})..."
      retry cleos_tx push action "${SIKA_TOKEN}" issue \
        "[\"sika.treas\",\"${TREAS_BOOTSTRAP_CGHS}\",\"SikaChainDev REX yield float\"]" \
        -p "${SIKA_ISSUER}@active" -x 3600
    fi
  fi

  push_action_or_skip "sika.treas setfx CGHS 1:1" \
    cleos_tx push action sika.treas setfx \
    "[\"${SIKA_SYSTEM}\",\"4,CGHS\",1000000,0]" \
    -p "${SIKA_SYSTEM}@active" -x 3600

  if [[ -n "${ORACLE_SIGN_KEY:-}" ]]; then
    echo "Registering oracle attestation key (setoraclekey)..."
    ORACLE_SIGN_KEY="${ORACLE_SIGN_KEY}" \
      ORACLE_REQUIRE_SIGNED="${ORACLE_REQUIRE_SIGNED:-0}" \
      node "${SCRIPT_DIR}/setup-oracle-key.mjs" || true
  fi

  echo "Seeding market payout prefs (§6.4)..."
  node "${SCRIPT_DIR}/seed-marketprefs.mjs" || true

  if [[ "${REX_DEV_SHORT_COOLDOWN:-1}" == "1" ]]; then
    echo "Setting dev REX unstake cooldown (${REX_UNSTAKE_SECONDS:-60}s)..."
    REX_UNSTAKE_SECONDS="${REX_UNSTAKE_SECONDS:-60}" bash "${SCRIPT_DIR}/set-rex-dev-params.sh" || true
  fi

  if [[ "${DEPLOY_MSIG:-1}" == "1" ]]; then
    bash "${SCRIPT_DIR}/deploy-msig.sh" || echo "  (${MSIG_ACCOUNT:-sika.msig} deploy skipped — see deploy-msig.sh)"
  fi

  if [[ "${TIER2_VESTING_ENABLE:-0}" == "1" ]]; then
    push_action_or_skip "eosio setvesting (Tier-2 vest scaffold)" \
      cleos_tx push action "${SIKA_SYSTEM}" setvesting \
      "[\"${SIKA_SYSTEM}\",1,31536000,8000]" \
      -p "${SIKA_SYSTEM}@active" -x 3600
  fi
}

echo "=== SikaChain system contract deploy ==="
echo "RPC: ${NODE_URL}"
echo "Contracts: ${BUILD_DIR}"
echo "Token: ${SIKA_TOKEN} | System: sika.system @ ${SIKA_SYSTEM}"
wait_for_node

echo "Unlocking dev wallet..."
"${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet open 2>/dev/null || true
if [[ -f "${ROOT}/wallet/.password" ]]; then
  DEV_PW="$(tr -d '\n' < "${ROOT}/wallet/.password")"
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet unlock --password "${DEV_PW}" 2>/dev/null || true
fi

for wasm in sika.token sika.system sika.rep sika.guard sika.rules sika.issue sika.treas; do
  if [[ ! -f "${BUILD_DIR}/${wasm}/${wasm}.wasm" ]]; then
    echo "error: missing ${BUILD_DIR}/${wasm}/${wasm}.wasm — run contracts/build.sh first"
    exit 1
  fi
done

node "${SCRIPT_DIR}/patch-system-abi.mjs" "${BUILD_DIR}/sika.system/sika.system.abi"

if [[ "${SIKA_UPGRADE_ONLY:-}" == "1" ]]; then
  echo "Upgrade-only: publishing WASM (no genesis bootstrap)"
  retry cleos_tx set contract "${SIKA_TOKEN}" "${BUILD_DIR}/sika.token/" -x 3600
  retry cleos_tx set contract "${SIKA_SYSTEM}" "${BUILD_DIR}/sika.system/" -x 3600
  for c in sika.guard sika.rep sika.rules sika.issue; do
    retry cleos_tx set contract "${c}" "${BUILD_DIR}/${c}/" -x 3600
  done
  deploy_satellite_contract sika.treas 700000
  ensure_treas_add_code

  echo "Ensuring settlement accounts exist..."
  for acct in sika.treas sika.cost sika.usd sika.oracle; do
    ensure_settlement_account "${acct}"
  done

  deploy_satellite_contract sika.treas 700000
  ensure_treas_add_code

  bootstrap_treas_settlement

  echo "=== Upgrade complete ==="
  cleos_cmd get currency stats "${SIKA_TOKEN}" SIKA || true
  cleos_cmd get table sika.treas sika.treas reserve 2>/dev/null || true
  exit 0
fi

SYSTEM_ACCOUNTS=(
  "${SIKA_TOKEN}" "${SIKA_REX}" sika.rep sika.guard sika.rules sika.issue
  sika.boost sika.bppay sika.burn sika.gold sika.cocoa sika.cngn sika.ckes
  sika.treas sika.cost sika.usd sika.oracle
)

echo "Creating system accounts..."
for acct in "${SYSTEM_ACCOUNTS[@]}"; do
  if account_exists "${acct}"; then
    echo "  (exists) ${acct}"
  else
    if ! cleos_tx create account "${SIKA_SYSTEM}" "${acct}" "${PUB}" -x 3600; then
      account_exists "${acct}" || {
        echo "  create failed for ${acct} — retrying once..." >&2
        sleep 1
        cleos_tx create account "${SIKA_SYSTEM}" "${acct}" "${PUB}" -x 3600 || true
      }
    fi
    wait_for_account "${acct}"
  fi
done

# Antelope protocol bootstrap (eosio.boot) — activates features before sika.system
EOSIO_BOOT_DIR=""
if [[ -f "${CORE_CONTRACTS_DIR}/eosio.boot/eosio.boot.wasm" ]]; then
  EOSIO_BOOT_DIR="${CORE_CONTRACTS_DIR}/eosio.boot"
elif [[ -f "${EOSIO_BOOT_FALLBACK}/eosio.boot.wasm" ]]; then
  EOSIO_BOOT_DIR="${EOSIO_BOOT_FALLBACK}"
fi
if [[ -z "${EOSIO_BOOT_DIR}" ]]; then
  echo "error: eosio.boot not found"
  echo "  tried: ${CORE_CONTRACTS_DIR}/eosio.boot/"
  echo "  tried: ${EOSIO_BOOT_FALLBACK}/"
  echo "Build with: bash scripts/build-system-contracts.sh (requires CDT)"
  exit 1
fi

echo "Activating protocol features (PREACTIVATE + Savanna)..."
PREACTIVATE_DIGEST="0ec7e080177b2c02b278d5088611686b49d739925a92d9bfcacd7fc6b74053bd"
wait_for_node
RESP=$(curl -s -X POST "http://127.0.0.1:${HTTP_PORT}/v1/producer/schedule_protocol_feature_activations" \
  -H "Content-Type: application/json" \
  -d "{\"protocol_features_to_activate\":[\"${PREACTIVATE_DIGEST}\"]}" || true)
if echo "${RESP}" | grep -q '"result":"ok"'; then
  echo "  scheduled PREACTIVATE_FEATURE"
  sleep 3
else
  echo "  PREACTIVATE schedule response: ${RESP:-connection failed}"
fi
wait_for_node

retry cleos_tx set contract "${SIKA_SYSTEM}" "${EOSIO_BOOT_DIR}/" -x 3600
sleep 3

FEATURES=(
  c3a6138c5061cf291310887c0b5c71fcaffeab90d5deb50d3b9e687cead45071
  d528b9f6e9693f45ed277af93474fd473ce7d831dae2180cca35d907bd10cb40
  5443fcf88330c586bc0e5f3dee10e7f63c76c00249c87fe4fbf7f38c082006b4
  f0af56d2c5a48d60a4a5b5c903edfb7db3a736a94ed589d0b797df33ff9d3e1d
  2652f5f96006294109b3dd0bbde63693f55324af452b799ee137a81a905eed25
  8ba52fe7a3956c5cd3a656a3174b931d3bb2abb45578befc59f283ecd816a405
  ad9e3d8f650687709fd68f4b90b41f7d825a365b02c23a636cef88ac2ac00c43
  68dcaa34c0517d19666e6b33add67351d8c5f69e999ca1e37931bc410a297428
  e0fb64b1085cc5538970158d05a009c24e276fb94e1a0bf6a528b48fbc4ff526
  ef43112c6543b88db2283a2e077278c315ae2c84719a8b25f25cc88565fbea99
  4a90c00d55454dc5b059055ca213579c6ea856967712a56017487886a4d4cc0f
  1a99a59d87e06e09ec5b028a9cbb7749b4a5ad8819004365d02dc4379a8b7241
  4e7bf348da00a945489b2a681749eb56f5de00b900014e137ddae39f48f69d67
  4fca8bd82bbd181e714e283f83e1b45d95ca5af40fb89ad3977b653c448f78c2
  299dcb6af692324b899b39f16d5a530a33062804e41f09dc97e9f156b4476707
  bcd2a26394b36614fd4894241d3c451ab0f6fd110958c3423073621a70826e99
  35c2186cc36f7bb4aeaf4487b36e57039ccf45a9136aa856a5d569ecca55ef2b
  6bcb40a24e49c26d0a60513b6aeb8551d264e4717f306b81a37a5afb3b47cedc
  63320dd4a58212e4d32d1f58926b73ca33a247326c2a5e9fd39268d2384e011a
  fce57d2331667353a0eac6b4209b67b843a7262a848af0a49a6e2fa9f6584eb4
  09e86cb0accf8d81c9e85d34bea4b925ae936626d00c984e4691186891f5bc16
  cbe0fafc8fcc6cc998395e9b6de6ebd94644467b1b4a97ec126005df07013c52
)
for f in "${FEATURES[@]}"; do
  push_action_or_skip "activate ${f}" \
    cleos_tx push action "${SIKA_SYSTEM}" activate "[\"${f}\"]" -p "${SIKA_SYSTEM}@active" -x 3600 || true
done
sleep 1

echo "Deploying sika.token → ${SIKA_TOKEN}..."
retry cleos_tx set contract "${SIKA_TOKEN}" "${BUILD_DIR}/sika.token/" -x 3600
sleep 1

if sika_token_created; then
  echo "  SIKA token already created — skipping create"
else
  echo "Creating SIKA token (max 8.64B)..."
  retry cleos_tx push action "${SIKA_TOKEN}" create "[\"${SIKA_SYSTEM}\",\"864000000000.0000 SIKA\"]" -p "${SIKA_TOKEN}@active" -x 3600
fi

if cghs_token_created; then
  echo "  CGHS token already created — skipping create"
else
  echo "Creating CGHS stablecoin (max 100B, issuer ${SIKA_ISSUER})..."
  retry cleos_tx push action "${SIKA_TOKEN}" create "[\"${SIKA_ISSUER}\",\"100000000000.0000 CGHS\"]" -p "${SIKA_TOKEN}@active" -x 3600
fi

if cusd_token_created; then
  echo "  CUSD reference token already created — skipping create"
else
  echo "Creating CUSD reference unit (max 10B, issuer ${SIKA_USD_ISSUER})..."
  retry cleos_tx push action "${SIKA_TOKEN}" create "[\"${SIKA_USD_ISSUER}\",\"10000000000.0000 CUSD\"]" -p "${SIKA_TOKEN}@active" -x 3600
fi

echo "Deploying sika.system → ${SIKA_SYSTEM}..."
retry cleos_tx set contract "${SIKA_SYSTEM}" "${BUILD_DIR}/sika.system/" -x 3600
sleep 2

if token_already_deployed; then
  echo "  genesis SIKA already issued — skipping init/issue"
else
  echo "Initializing system contract..."
  push_action_or_skip "init" \
    cleos_tx push action "${SIKA_SYSTEM}" init "[0,\"4,SIKA\"]" -p "${SIKA_SYSTEM}@active" -x 3600

  echo "Issuing initial SIKA to ${SIKA_SYSTEM} (dev bootstrap — 1B for testing)..."
  retry cleos_tx push action "${SIKA_TOKEN}" issue "[\"${SIKA_SYSTEM}\",\"1000000000.0000 SIKA\",\"SikaChainDev genesis\"]" -p "${SIKA_SYSTEM}@active" -x 3600
fi

echo "Deploying satellite contracts..."
for c in sika.guard sika.rep sika.rules sika.issue; do
  deploy_satellite_contract "${c}"
done
deploy_satellite_contract sika.treas 600000
ensure_treas_add_code

bootstrap_treas_settlement

echo "=== Deploy complete ==="
cleos_cmd get currency stats "${SIKA_TOKEN}" SIKA || true
cleos_cmd get currency stats "${SIKA_TOKEN}" CGHS || true
cleos_cmd get table "${SIKA_SYSTEM}" "${SIKA_SYSTEM}" global || true
echo "Token: SIKA + CGHS @ ${SIKA_TOKEN} | System: sika.system @ ${SIKA_SYSTEM}"
