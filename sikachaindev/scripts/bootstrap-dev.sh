#!/usr/bin/env bash
# Bootstrap SikaChainDev: start daemons, unlock wallet, deploy contracts if missing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

echo "=== SikaChainDev bootstrap ==="

bash "${SCRIPT_DIR}/start-all.sh"

echo ""
bash "${SCRIPT_DIR}/setup-wallet.sh"

echo ""
is_sika_token_ready() {
  "${CLEOS}" --url "${NODE_URL}" get currency stats sika.token SIKA 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); s=d.get('SIKA',{}).get('supply','0').split()[0]; sys.exit(0 if float(s)>0 else 1)" 2>/dev/null
}

echo "Waiting for chain RPC (replay may take a few seconds)..."
DEPLOYED=0
for _ in $(seq 1 60); do
  if is_sika_token_ready; then
    DEPLOYED=1
    break
  fi
  curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null 2>&1 || true
  sleep 1
done

if [[ "${DEPLOYED}" -eq 1 ]]; then
  echo "sika.token already deployed — skipping deploy"
else
  echo "Deploying Sika system contracts..."
  bash "${SCRIPT_DIR}/deploy-sika-system.sh"
fi

echo ""
ACCOUNT_EXISTS=0
if curl -sf "${NODE_URL}/v1/chain/get_account" \
  -H 'Content-Type: application/json' \
  -d '{"account_name":"sikadev"}' | grep -q '"account_name"'; then
  ACCOUNT_EXISTS=1
fi

if [[ "${ACCOUNT_EXISTS}" -eq 0 ]] && is_sika_token_ready; then
  echo "Creating dev account sikadev..."
  PUB=$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['accounts']['sikadev']['publicKey'])")
  bash "${SCRIPT_DIR}/create-account.sh" sikadev "${PUB}" || echo "  (create sikadev failed — chain may need manual setup)"
else
  echo "sikadev already exists — skipping create"
fi

if [[ "${ACCOUNT_EXISTS}" -eq 0 ]] && ! is_sika_token_ready; then
  echo "Skipping sikadev create — deploy SIKA token first (run deploy-sika-system.sh)"
fi

echo ""
if curl -sf "${NODE_URL}/v1/chain/get_account" \
  -H 'Content-Type: application/json' \
  -d '{"account_name":"sikadev"}' | grep -q '"account_name"'; then
  SIKADEV_BAL=$("${CLEOS}" --url "${NODE_URL}" get currency balance sika.token sikadev SIKA 2>/dev/null | tr -d '\n' || true)
  if [[ -z "${SIKADEV_BAL}" ]]; then
    echo "Funding sikadev with 10000.0000 SIKA for wallet testing..."
    if [[ -f "${ROOT}/wallet/.password" ]]; then
      DEV_PW="$(tr -d '\n' < "${ROOT}/wallet/.password")"
      "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet unlock --password "${DEV_PW}" 2>/dev/null || true
    fi
    if "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" transfer eosio sikadev "10000.0000 SIKA" "SikaChainDev bootstrap" -c sika.token; then
      echo "  funded sikadev"
    else
      echo "  (fund transfer failed — check eosio balance and wallet)"
    fi
  fi
fi

echo ""
bash "${SCRIPT_DIR}/status.sh"

echo ""
echo "Next:"
echo "  Bindings: bash scripts/generate-bindings.sh"
echo "  App:  cp \"Sika app/.env.sikachaindev\" \"Sika app/.env.local\" && cd \"Sika app\" && npm run dev"
echo "  API:  cd \"wharfkit adapter\" && cp .env.example .env && npm run dev"
