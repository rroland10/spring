#!/usr/bin/env bash
# Register and vote in 21 block producers on a running SikaChainDev chain.
#
# Lightweight mode (default): works with the existing single nodeos. With
# enable-stale-production the dev node keeps advancing blocks while the on-chain
# producer schedule lists all 21 sikabp* accounts — enough for vote UI / Hyperion
# testing.
#
# For real 21-way block rotation, run bootstrap-21bp.sh first, then
# start-21bp-cluster.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

PRODUCERS_JSON="${PRODUCERS_JSON:-${ROOT}/config/producers-21.json}"
KEY_FORMAT_MJS="${SCRIPT_DIR}/lib/key-format.mjs"
SYMBOL="${SIKA_SYMBOL:-SIKA}"
STAKE_NET="${BP_STAKE_NET:-5000.0000 ${SYMBOL}}"
STAKE_CPU="${BP_STAKE_CPU:-5000.0000 ${SYMBOL}}"
RAM_BYTES="${BP_RAM_BYTES:-8192}"
VOTER="${BP_VOTER:-}"  # default: each staked producer votes (sikaio cannot self-stake SIKA)

cleos_cmd() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

retry() { local n=0; until "$@" || [[ $((n+=1)) -ge 8 ]]; do sleep 1; done; }

wait_for_node() {
  local n=0
  until curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null 2>&1; do
    n=$((n + 1))
    if [[ $n -ge 60 ]]; then
      echo "error: nodeos not responding at ${NODE_URL}"
      exit 1
    fi
    sleep 1
  done
}

unlock_wallet() {
  local pw_file="${ROOT}/wallet/.password"
  if [[ -f "${pw_file}" ]]; then
    cleos_cmd wallet open 2>/dev/null || true
    cleos_cmd wallet unlock --password "$(tr -d '\n' < "${pw_file}")" 2>/dev/null || true
  fi
}

account_exists() {
  curl -sf "${NODE_URL}/v1/chain/get_account" \
    -H 'Content-Type: application/json' \
    -d "{\"account_name\":\"$1\"}" | grep -q '"account_name"'
}

producer_registered() {
  cleos_cmd get table "${SIKA_SYSTEM_ACCOUNT}" "${SIKA_SYSTEM_ACCOUNT}" producers -l 500 2>/dev/null \
    | grep -q "\"owner\": \"$1\""
}

stake_for_producer() {
  local name="$1"
  local funder="${2:-${SIKA_SYSTEM_ACCOUNT}}"
  local total_stake
  total_stake="$(python3 - <<'PY' "${STAKE_NET}" "${STAKE_CPU}"
import sys
def amt(s):
    return float(s.split()[0])
print(f"{amt(sys.argv[1]) + amt(sys.argv[2]):.4f}")
PY
)"
  echo "  funding ${name} with ${total_stake} ${SYMBOL} for self-stake..."
  retry cleos_cmd transfer "${funder}" "${name}" "${total_stake} ${SYMBOL}" "BP stake" -c sika.token -p "${funder}@active"
  retry cleos_cmd push action "${SIKA_SYSTEM_ACCOUNT}" delegatebw \
    "[\"${name}\",\"${name}\",\"${STAKE_NET}\",\"${STAKE_CPU}\",false]" \
    -p "${name}@active"
}

echo "=== SikaChainDev — bootstrap 21 block producers ==="
echo "RPC:    ${NODE_URL}"
echo "Voter:  ${VOTER:-all 21 producers (staked)}"
echo "Config: ${PRODUCERS_JSON}"
echo ""

if [[ ! -f "${PRODUCERS_JSON}" ]]; then
  echo "error: missing ${PRODUCERS_JSON}"
  exit 1
fi

if ! curl -sf "${NODE_URL}/v1/chain/get_account" \
  -H 'Content-Type: application/json' \
  -d '{"account_name":"sika.token"}' | grep -q '"account_name"'; then
  echo "error: sika.token not deployed — run bootstrap-dev.sh first"
  exit 1
fi

wait_for_node
unlock_wallet

GUARD_BAL="$(cleos_cmd get currency balance sika.token sika.guard SIKA 2>/dev/null | awk '{print $1}' || echo 0)"
if python3 - <<'PY' "${GUARD_BAL}"
import sys
sys.exit(0 if float(sys.argv[1] or 0) >= 2500 else 1)
PY
then
  :
else
  echo "Funding sika.guard for account RAM (create-account fee payer)..."
  retry cleos_cmd transfer "${SIKA_SYSTEM_ACCOUNT}" sika.guard "3000.0000 ${SYMBOL}" "BP bootstrap RAM" -c sika.token -p "${SIKA_SYSTEM_ACCOUNT}@active"
fi

echo "Importing producer keys into keosd..."
python3 - <<'PY' "${PRODUCERS_JSON}" "${CLEOS}" "${NODE_URL}" "${WALLET_URL}"
import json, subprocess, sys
path, cleos, url, wallet = sys.argv[1:5]
keys = json.load(open(path))["producers"]
existing = subprocess.run(
    [cleos, "--url", url, "--wallet-url", wallet, "wallet", "keys"],
    capture_output=True, text=True,
).stdout
for p in keys:
    if p["pub"] in existing:
        continue
    subprocess.run(
        [cleos, "--url", url, "--wallet-url", wallet, "wallet", "import", "--private-key", p["pvt"]],
        check=True,
    )
PY

created=0
registered=0
while IFS=$'\t' read -r name pub; do
  pub_k1="$(node "${KEY_FORMAT_MJS}" to-pub-k1 "${pub}")"

  if account_exists "${name}"; then
    echo "  (exists) ${name}"
  else
    echo "Creating account ${name} (${RAM_BYTES} bytes RAM)..."
    RAM_BYTES="${RAM_BYTES}" bash "${SCRIPT_DIR}/create-account.sh" "${name}" "${pub_k1}"
    stake_for_producer "${name}"
    created=$((created + 1))
  fi

  if account_exists "${name}" && ! producer_registered "${name}"; then
    net_staked="$(cleos_cmd get table "${SIKA_SYSTEM_ACCOUNT}" "${name}" userres 2>/dev/null \
      | python3 -c "import json,sys; r=json.load(sys.stdin).get('rows',[]); print(r[0]['net_weight'] if r else '0')" 2>/dev/null || echo 0)"
    if python3 - <<'PY' "${net_staked}"
import sys
sys.exit(0 if float(str(sys.argv[1]).split()[0]) > 0 else 1)
PY
    then
      :
    else
      echo "Staking ${name}..."
      stake_for_producer "${name}"
    fi
  fi

  if producer_registered "${name}"; then
    echo "  (registered) ${name}"
  else
    echo "Registering producer ${name}..."
    retry cleos_cmd system regproducer "${name}" "${pub}" "https://${name}.sikachain.dev" -p "${name}@active"
    registered=$((registered + 1))
  fi
done < <(python3 - <<'PY' "${PRODUCERS_JSON}"
import json, sys
for p in json.load(open(sys.argv[1]))["producers"]:
    print(f"{p['name']}\t{p['pub']}")
PY
)

PRODUCER_NAMES=()
while IFS= read -r n; do
  PRODUCER_NAMES+=("${n}")
done < <(python3 - <<'PY' "${PRODUCERS_JSON}"
import json, sys
for p in json.load(open(sys.argv[1]))["producers"]:
    print(p["name"])
PY
)

echo ""
if [[ "${SKIP_BP_VOTE:-0}" == "1" ]]; then
  echo "  (skip) voteproducer — single-node docker (avoid Savanna schedule activation)"
elif [[ -n "${VOTER}" ]]; then
  echo "Voting ${VOTER} for all 21 producers..."
  retry cleos_cmd system voteproducer prods "${VOTER}" "${PRODUCER_NAMES[@]}" -p "${VOTER}@active"
else
  echo "Voting from each staked producer for the full set..."
  for voter in "${PRODUCER_NAMES[@]}"; do
    retry cleos_cmd system voteproducer prods "${voter}" "${PRODUCER_NAMES[@]}" -p "${voter}@active"
  done
fi

echo ""
echo "Active producer schedule (top 21):"
cleos_cmd system listproducers -l 21 || true

echo ""
echo "Done. Created ${created} accounts, registered ${registered} new producers."
echo "  Vote UI / rankings: ready on ${NODE_URL}"
echo "  6-BP rotation:      bash scripts/start-6bp-cluster.sh"
echo "  21-BP rotation:     bash scripts/start-21bp-cluster.sh"
