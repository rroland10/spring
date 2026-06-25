#!/usr/bin/env bash
# Ghana v1 / sika-account launch readiness — offline templates + optional live chain.
#
# Usage:
#   bash scripts/check-launch-ready.sh              # templates + chain if RPC up
#   LIVE=1 bash scripts/check-launch-ready.sh       # + verify-gh-v1 Playwright gate
#   FULL=1 bash scripts/check-launch-ready.sh       # + GH_V1=1 test-wallet-live (slow)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
WEB_DIR="${SIKA_CHAIN_WEB_DIR:-/Users/randallroland/Desktop/Projects/SikaChain}"
CHAIN_JSON="${ROOT}/chain.json"
ANCHOR_JSON="${ROOT}/anchor-chain.json"

FAIL=0
check() {
  local label="$1"
  shift
  if "$@"; then
    echo "  ok  ${label}"
  else
    echo "  FAIL ${label}" >&2
    FAIL=1
  fi
}

echo "=== check-launch-ready (sika system account + gh-v1) ==="
echo ""

echo "--- Spring build ---"
check "SIKACHAIN=ON in Spring build" bash "${SCRIPT_DIR}/check-spring-sikachain.sh" >/dev/null

echo ""
echo "--- chain.json / anchor ---"
check "chain.json systemContract=sika producer=sikaio" python3 - <<'PY' "${CHAIN_JSON}"
import json, sys
c = json.load(open(sys.argv[1]))
sys.exit(0 if c.get("systemContract") == "sika" and c.get("producer") == "sikaio" else 1)
PY

check "chain.json has sikaio protocol account" python3 - <<'PY' "${CHAIN_JSON}"
import json, sys
c = json.load(open(sys.argv[1]))
sys.exit(0 if c.get("protocolAccount") == "sikaio" and "sikaio" in c.get("accounts", {}) else 1)
PY

check "chain.json has no eosio account entry" python3 - <<'PY' "${CHAIN_JSON}"
import json, sys
c = json.load(open(sys.argv[1]))
sys.exit(0 if "eosio" not in c.get("accounts", {}) else 1)
PY

check "anchor-chain.json systemContract=sika protocol=sikaio" python3 - <<'PY' "${ANCHOR_JSON}"
import json, sys
c = json.load(open(sys.argv[1]))
sys.exit(0 if c.get("systemContract") == "sika" and c.get("protocolAccount") == "sikaio" else 1)
PY

TESTNET_ANCHOR="${ROOT}/anchor-chain.testnet.example.json"
if [[ -f "${TESTNET_ANCHOR}" ]]; then
  check "testnet anchor example systemContract=sika" python3 - <<'PY' "${TESTNET_ANCHOR}"
import json, sys
c = json.load(open(sys.argv[1]))
sys.exit(0 if c.get("systemContract") == "sika" and "REPLACE" in c.get("chainId", "") else 1)
PY
fi

echo ""
echo "--- App / adapter env templates ---"
bash "${SCRIPT_DIR}/sync-dev-env.sh" >/dev/null 2>&1 || true

GH_V1_ENV="${APP_DIR}/.env.sikachaindev.gh-v1"
PROD_EXAMPLE="${APP_DIR}/.env.production.gh-v1.example"

check "Sika app .env.sikachaindev.gh-v1" test -f "${GH_V1_ENV}"
check "gh-v1 env has NEXT_PUBLIC_CONTRACT_ACCOUNT=sika" grep -q '^NEXT_PUBLIC_CONTRACT_ACCOUNT=sika' "${GH_V1_ENV}" 2>/dev/null
check "gh-v1 env has NEXT_PUBLIC_PROTOCOL_ACCOUNT=sikaio" grep -q '^NEXT_PUBLIC_PROTOCOL_ACCOUNT=sikaio' "${GH_V1_ENV}" 2>/dev/null
check "gh-v1 env has NEXT_PUBLIC_WALLET_ROLLOUT=gh-v1" grep -q '^NEXT_PUBLIC_WALLET_ROLLOUT=gh-v1' "${GH_V1_ENV}" 2>/dev/null
check "production example .env.production.gh-v1.example" test -f "${PROD_EXAMPLE}"
check "production example has no DEV_WALLET" bash -c "! grep -q '^NEXT_PUBLIC_DEV_WALLET=1' '${PROD_EXAMPLE}'"

if [[ -f "${WEB_DIR}/src/lib/chain-constants.ts" ]]; then
  check "GTM chain-constants references sika system" grep -q "systemContract.*sika\|'sika'" "${WEB_DIR}/src/lib/chain-constants.ts" 2>/dev/null
  check "GTM chain-constants protocolAccount=sikaio" grep -q '"protocolAccount": "sikaio"' "${WEB_DIR}/src/lib/chain-constants.ts" 2>/dev/null
else
  echo "  skip GTM chain-constants (SIKA_CHAIN_WEB_DIR not found)"
fi

echo ""
echo "--- Live chain (optional) ---"
if curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null 2>&1; then
  export SIKACHAIN_DEV=1
  if bash "${SCRIPT_DIR}/verify-phase3.sh"; then
    echo "  ok  verify-phase3"
  else
    echo "  FAIL verify-phase3" >&2
    FAIL=1
  fi

  check "eosio account absent on chain (legacy)" bash -c "
    ! curl -sf '${NODE_URL}/v1/chain/get_account' \
      -H 'Content-Type: application/json' \
      -d '{\"account_name\":\"eosio\"}' | grep -q '\"account_name\"'
  "
  check "sikaio protocol account on chain" bash -c "
    curl -sf '${NODE_URL}/v1/chain/get_account' \
      -H 'Content-Type: application/json' \
      -d '{\"account_name\":\"sikaio\"}' | grep -q '\"privileged\":true'
  "
else
  echo "  skip live chain (RPC down at ${NODE_URL})"
fi

if [[ "${FAIL}" -ne 0 ]]; then
  echo ""
  echo "=== check-launch-ready FAILED ===" >&2
  exit 1
fi

echo ""
echo "=== check-launch-ready — templates OK ==="

if [[ "${LIVE:-0}" == "1" || "${FULL:-0}" == "1" ]]; then
  echo ""
  bash "${SCRIPT_DIR}/verify-gh-v1.sh"
fi

if [[ "${FULL:-0}" == "1" ]]; then
  echo ""
  GH_V1=1 PLAYWRIGHT_REUSE_SERVER=1 bash "${SCRIPT_DIR}/test-wallet-live.sh"
fi

echo ""
echo "=== check-launch-ready complete ==="
