#!/usr/bin/env bash
# Full Sika app feature matrix via cleos + keosd (no browser).
#
# Covers wallet flows the app uses: balances, SIKA/CGHS send, vote, REX, RAM,
# delegate bandwidth, MSIG (system + business), account creation, NFTs.
#
# Usage:
#   bash scripts/test-app-cleos-full.sh
#   VERIFY_TIER2=1 bash scripts/test-app-cleos-full.sh   # + vesting smoke (slow)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

SYS="${SIKA_SYSTEM_ACCOUNT:-sika}"
TOKEN="${SIKA_TOKEN_ACCOUNT:-sika.token}"
DEV="${CLEOS_TEST_ACCOUNT:-sikadev}"
FAIL=0

cleos_cmd() {
  bash "${SCRIPT_DIR}/cleos.sh" "$@"
}

run() {
  local label="$1"
  shift
  printf "  %-46s " "${label}"
  if "$@" >/dev/null 2>&1; then
    echo "ok"
  else
    echo "FAIL"
    FAIL=1
  fi
}

run_script() {
  local label="$1"
  shift
  printf "  %-46s " "${label}"
  if "$@" 2>&1 | tail -3; then
    :
  fi
  if [[ "${PIPESTATUS[0]}" -eq 0 ]]; then
    echo "ok"
  else
    echo "FAIL"
    FAIL=1
  fi
}

echo "=== test-app-cleos-full (Sika app features via cleos) ==="
echo "  system=${SYS}  dev=${DEV}  RPC=${NODE_URL}"
echo ""

bash "${SCRIPT_DIR}/wait-for-rpc.sh" 60
cleos_wallet_ready

echo "--- Core cleos matrix (test-cleos.sh) ---"
if VERIFY_REX=1 VERIFY_VOTE=1 CREATE_ACCOUNT=1 VERIFY_MSIG=1 \
  bash "${SCRIPT_DIR}/test-cleos.sh"; then
  echo "  test-cleos.sh                                  ok"
else
  echo "  test-cleos.sh                                  FAIL"
  FAIL=1
fi

echo ""
echo "--- Dev accounts smoke ---"
run "smoke-dev-accounts" bash "${SCRIPT_DIR}/smoke-dev-accounts.sh"

echo ""
echo "--- Resources (RAM + stake) ---"
run "buyrambytes sikadev +4KiB" cleos_cmd push action "${SYS}" buyrambytes \
  '["sika.guard","'"${DEV}"'",4096]' -p sika.guard@active -x 3600
run "delegatebw ${DEV} (small)" cleos_cmd push action "${SYS}" delegatebw \
  "[\"${DEV}\",\"${DEV}\",\"1.0000 SIKA\",\"1.0000 SIKA\",false]" -p "${DEV}@active" -x 3600
run "stake reflected on account" bash -c "
  bash '${SCRIPT_DIR}/cleos.sh' get account '${DEV}' \
    | grep -q 'delegated:'
"

echo ""
echo "--- Business multisig (sikadev proposer) ---"
if bash "${SCRIPT_DIR}/verify-msig-business.sh"; then
  echo "  verify-msig-business                            ok"
else
  echo "  verify-msig-business                            FAIL"
  FAIL=1
fi

echo ""
echo "--- NFTs (AtomicAssets) ---"
if bash "${SCRIPT_DIR}/mint-nft-dev.sh"; then
  echo "  mint-nft-dev                                    ok"
else
  echo "  mint-nft-dev                                    FAIL"
  FAIL=1
fi

echo ""
echo "--- Settlement / treasury tables ---"
run "treas reserve" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_table_rows' -H 'Content-Type: application/json' \
    -d '{\"json\":true,\"code\":\"sika.treas\",\"scope\":\"sika.treas\",\"table\":\"reserve\",\"limit\":1}' \
    | python3 -c \"import json,sys; json.load(sys.stdin)\"
"
run "fxquotes oracle" bash -c "
  curl -sf '${NODE_URL}/v1/chain/get_table_rows' -H 'Content-Type: application/json' \
    -d '{\"json\":true,\"code\":\"sika.treas\",\"scope\":\"sika.treas\",\"table\":\"fxquotes\",\"limit\":1}' \
    | python3 -c \"import json,sys; json.load(sys.stdin)\"
"

echo ""
echo "--- Vote proxy (regproxy + voteproducer proxy) ---"
if PROXY_ACCOUNT=sikauser1 VOTER_ACCOUNT=sikauser2 bash "${SCRIPT_DIR}/verify-proxy.sh"; then
  echo "  verify-proxy                                    ok"
else
  echo "  verify-proxy                                    FAIL"
  FAIL=1
fi

if [[ "${VERIFY_TIER2:-0}" == "1" ]]; then
  echo ""
  echo "--- Tier-2 vesting ---"
  if SIKA_VEST_SECONDS="${SIKA_VEST_SECONDS:-60}" bash "${SCRIPT_DIR}/verify-tier2-vesting.sh"; then
    echo "  verify-tier2-vesting                            ok"
  else
    echo "  verify-tier2-vesting                            FAIL"
    FAIL=1
  fi
else
  echo ""
  echo "--- Tier-2 vesting ---"
  echo "  SKIP (set VERIFY_TIER2=1 to run ~60s vesting smoke)"
fi

echo ""
if [[ "${FAIL}" -eq 0 ]]; then
  echo "=== test-app-cleos-full complete — all checks passed ==="
  echo ""
  echo "App UI parity: run WALLET_UI=1 bash scripts/test-features.sh for Playwright"
else
  echo "=== test-app-cleos-full failed ===" >&2
  exit 1
fi
