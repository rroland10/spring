#!/usr/bin/env bash
# Test SikaChainDev protocol features via cleos + keosd (no browser, no Node tx builder).
#
# Usage:
#   bash scripts/test-cleos.sh
#   VERIFY_MSIG=1 bash scripts/test-cleos.sh
#   VERIFY_REX=1 bash scripts/test-cleos.sh
#   CREATE_ACCOUNT=1 bash scripts/test-cleos.sh   # cleos newaccount smoke
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

DEV_CHAIN_ID="9b2fde923758593c09517f77ed445a3962a9c938f44405dac43b4ccfebbfa57e"
if [[ -z "${SIKA_SYSTEM_PRIVATE_KEY:-}" ]]; then
  chain_id="$(curl -sf "${NODE_URL}/v1/chain/get_info" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('chain_id',''))" 2>/dev/null || true)"
  if [[ -n "${chain_id}" && "${chain_id}" != "${DEV_CHAIN_ID}" && -f "${ROOT}/config/testnet/generated/README.txt" ]]; then
    SIKA_SYSTEM_PRIVATE_KEY="$(grep '^Genesis private:' "${ROOT}/config/testnet/generated/README.txt" | awk '{print $3}')"
    export SIKA_SYSTEM_PRIVATE_KEY
  fi
fi
if [[ -n "${SIKA_SYSTEM_PRIVATE_KEY:-}" ]]; then
  cleos wallet open 2>/dev/null || true
  if [[ -f "${ROOT}/wallet/.password" ]]; then
    "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet unlock \
      --password "$(tr -d '\n' < "${ROOT}/wallet/.password")" 2>/dev/null || true
  fi
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet import \
    --private-key "${SIKA_SYSTEM_PRIVATE_KEY}" 2>/dev/null || true
fi

SYS="${SIKA_SYSTEM_ACCOUNT:-sika}"
TOKEN="${SIKA_TOKEN_ACCOUNT:-sika.token}"
DEV="${CLEOS_TEST_ACCOUNT:-sikadev}"
PEER="${CLEOS_PEER_ACCOUNT:-sikauser1}"
FAIL=0

cleos_cmd() {
  bash "${SCRIPT_DIR}/cleos.sh" "$@"
}

run() {
  local label="$1"
  shift
  printf "  %-44s " "${label}"
  if "$@" >/dev/null 2>&1; then
    echo "ok"
  else
    echo "FAIL"
    FAIL=1
  fi
}

echo "=== test-cleos (cleos + keosd feature matrix) ==="
echo "  system=${SYS}  dev=${DEV}  RPC=${NODE_URL}"
echo ""

bash "${SCRIPT_DIR}/wait-for-rpc.sh" 60
cleos_wallet_ready

echo "--- Wallet ---"
run "keosd list_wallets" bash -c "bash '${SCRIPT_DIR}/cleos.sh' wallet list | grep -qi default"
run "wallet keys present" bash -c "bash '${SCRIPT_DIR}/cleos.sh' wallet keys | grep -qE 'PUB_K1_|EOS'"

echo ""
echo "--- Chain queries ---"
run "cleos get info" cleos_cmd get info
run "cleos get account ${SYS}" cleos_cmd get account "${SYS}"
run "cleos get account ${DEV}" cleos_cmd get account "${DEV}"
run "SIKA currency stats" cleos_cmd get currency stats "${TOKEN}" SIKA
run "CGHS currency stats" cleos_cmd get currency stats "${TOKEN}" CGHS
run "SIKA balance ${DEV}" bash -c "
  bash '${SCRIPT_DIR}/cleos.sh' get currency balance '${TOKEN}' '${DEV}' SIKA \
    | python3 -c \"import sys; b=sys.stdin.read().strip(); sys.exit(0 if b and float(b.split()[0])>0 else 1)\"
"
run "CGHS balance ${DEV}" bash -c "
  bash '${SCRIPT_DIR}/cleos.sh' get currency balance '${TOKEN}' '${DEV}' CGHS \
    | python3 -c \"import sys; b=sys.stdin.read().strip(); sys.exit(0 if b and float(b.split()[0])>0 else 1)\"
"

echo ""
echo "--- System tables (cleos get table) ---"
run "rammarket @${SYS}" cleos_cmd get table "${SYS}" "${SYS}" rammarket
run "rexpool @${SYS}" cleos_cmd get table "${SYS}" "${SYS}" rexpool
run "producers @${SYS}" cleos_cmd get table "${SYS}" "${SYS}" producers -l 5
run "delband ${DEV}" cleos_cmd get table "${SYS}" "${DEV}" delband -l 5
run "voters @${SYS}" cleos_cmd get table "${SYS}" "${SYS}" voters -l 5
run "treas reserve" cleos_cmd get table sika.treas sika.treas reserve

echo ""
echo "--- On-chain actions (cleos transfer / vote) ---"
run "transfer SIKA ${DEV}→${PEER}" bash "${SCRIPT_DIR}/verify-peer-transfer.sh"
run "transfer CGHS ${DEV}→sikauser2" bash -c \
  "PEER_TO=sikauser2 PEER_SYMBOL=CGHS bash '${SCRIPT_DIR}/verify-peer-transfer.sh'"
run "listproducers" cleos_cmd system listproducers -l 6

if [[ "${VERIFY_VOTE:-0}" == "1" ]]; then
  run "deposit (voter init)" bash -c "
    bash '${SCRIPT_DIR}/cleos.sh' push action '${SYS}' deposit '[\"${DEV}\",\"10.0000 SIKA\"]' -p '${DEV}@active' -x 3600
  "
  run "voteproducer prods" bash -c "
    bash '${SCRIPT_DIR}/cleos.sh' system voteproducer prods '${DEV}' sikabpa sikabpb sikabpc -p '${DEV}@active' -x 3600
  "
else
  echo "  voteproducer prods                           -- (set VERIFY_VOTE=1 to broadcast)"
fi

if [[ "${CREATE_ACCOUNT:-0}" == "1" ]]; then
  echo ""
  echo "--- Account creation (cleos) ---"
  ACCT="$(msig_proposal_name cle)"
  if bash "${SCRIPT_DIR}/create-account-cleos.sh" "${ACCT}"; then
    echo "  create-account-cleos ${ACCT}                 ok"
    run "get account ${ACCT}" bash -c "
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        curl -sf '${NODE_URL}/v1/chain/get_account' -H 'Content-Type: application/json' \
          -d '{\"account_name\":\"${ACCT}\"}' | grep -q account_name && exit 0
        sleep 0.5
      done
      exit 1
    "
  else
    echo "  create-account-cleos ${ACCT}                 FAIL"
    FAIL=1
  fi
else
  echo "  create-account-cleos                       -- (set CREATE_ACCOUNT=1 to run)"
fi

if [[ "${VERIFY_MSIG:-1}" == "1" ]]; then
  echo ""
  echo "--- Multisig (cleos push action sika.msig) ---"
  if bash "${SCRIPT_DIR}/verify-msig.sh"; then
    echo "  verify-msig                                  ok"
  else
    echo "  verify-msig                                  FAIL"
    FAIL=1
  fi
else
  echo ""
  echo "--- Multisig ---"
  echo "  SKIP (VERIFY_MSIG=0)"
fi

if [[ "${VERIFY_REX:-0}" == "1" ]]; then
  echo ""
  echo "--- REX (cleos push action ${SYS}) ---"
  if bash "${SCRIPT_DIR}/verify-rex-unstake.sh"; then
    echo "  verify-rex-unstake                           ok"
  else
    echo "  verify-rex-unstake                           FAIL"
    FAIL=1
  fi
else
  echo ""
  echo "--- REX ---"
  echo "  SKIP (set VERIFY_REX=1 for stake/sellrex/refund)"
fi

echo ""
if [[ "${FAIL}" -eq 0 ]]; then
  echo "=== test-cleos complete — all checks passed ==="
else
  echo "=== test-cleos failed ===" >&2
  exit 1
fi
