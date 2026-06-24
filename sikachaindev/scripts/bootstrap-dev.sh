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

echo "Waiting for chain RPC..."
bash "${SCRIPT_DIR}/wait-for-rpc.sh" 180
DEPLOYED=0
if is_sika_token_ready; then
  DEPLOYED=1
fi

if [[ "${DEPLOYED}" -eq 1 ]]; then
  echo "sika.token already deployed — skipping deploy"
else
  echo "Deploying Sika system contracts..."
  bash "${SCRIPT_DIR}/deploy-sika-system.sh"
fi

msig_ready() {
  curl -sf "${NODE_URL}/v1/chain/get_account" -d "{\"account_name\":\"${MSIG_ACCOUNT}\"}" 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('privileged') else 1)" 2>/dev/null
}

if is_sika_token_ready && ! msig_ready; then
  echo "Ensuring ${MSIG_ACCOUNT} (privileged multisig)..."
  bash "${SCRIPT_DIR}/deploy-msig.sh" || echo "  (deploy-msig failed — see deploy-msig.sh)"
fi

atomicassets_ready() {
  curl -sf "${NODE_URL}/v1/chain/get_code" \
    -H 'Content-Type: application/json' \
    -d '{"account_name":"atomicassets"}' \
    | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('wasm') else 1)" 2>/dev/null
}

if is_sika_token_ready && [[ "${DEPLOY_ATOMICASSETS:-0}" == "1" ]] && ! atomicassets_ready; then
  echo "Ensuring atomicassets NFT contract..."
  bash "${SCRIPT_DIR}/deploy-atomicassets.sh" || echo "  (deploy-atomicassets failed)"
fi

echo ""
node "${SCRIPT_DIR}/sync-app-env.mjs" 2>/dev/null || true
ACCOUNT_EXISTS=0
if curl -sf "${NODE_URL}/v1/chain/get_account" \
  -H 'Content-Type: application/json' \
  -d '{"account_name":"sikadev"}' | grep -q '"account_name"'; then
  ACCOUNT_EXISTS=1
fi

if [[ "${ACCOUNT_EXISTS}" -eq 0 ]] && is_sika_token_ready; then
  echo "Creating dev account sikadev..."
  PUB=$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['accounts']['sikadev']['publicKey'])")
  RAM_BYTES=65536 bash "${SCRIPT_DIR}/create-account.sh" sikadev "${PUB}" || echo "  (create sikadev failed — chain may need manual setup)"
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
  SIKADEV_RAM=$("${CLEOS}" --url "${NODE_URL}" get account sikadev -j 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('ram_quota',0))" 2>/dev/null || echo "0")
  if [[ "${SIKADEV_RAM}" -lt 32768 ]]; then
    need=$(( 65536 - SIKADEV_RAM + 4096 ))
    echo "Ensuring sikadev RAM (quota ${SIKADEV_RAM} → +${need} bytes)..."
    "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" push action "${SIKA_SYSTEM_ACCOUNT}" buyrambytes \
      "[\"sika.guard\",\"sikadev\",${need}]" -p sika.guard@active --return-failure-trace false --use-old-rpc >/dev/null \
      || echo "  (buyram for sikadev failed — msig proposals may need more RAM)"
  fi
  SIKADEV_BAL=$("${CLEOS}" --url "${NODE_URL}" get currency balance sika.token sikadev SIKA 2>/dev/null | tr -d '\n' || true)
  if [[ -z "${SIKADEV_BAL}" ]]; then
    echo "Funding sikadev with 10000.0000 SIKA for wallet testing..."
    if [[ -f "${ROOT}/wallet/.password" ]]; then
      DEV_PW="$(tr -d '\n' < "${ROOT}/wallet/.password")"
      "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet unlock --password "${DEV_PW}" 2>/dev/null || true
    fi
    if "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" transfer "${SIKA_SYSTEM_ACCOUNT}" sikadev "10000.0000 SIKA" "SikaChainDev bootstrap" -c sika.token; then
      echo "  funded sikadev with SIKA"
    else
      echo "  (SIKA fund transfer failed — check ${SIKA_SYSTEM_ACCOUNT} balance and wallet)"
    fi
  fi

  SIKADEV_CGHS=$("${CLEOS}" --url "${NODE_URL}" get currency balance sika.token sikadev CGHS 2>/dev/null | tr -d '\n' || true)
  if [[ -z "${SIKADEV_CGHS}" ]]; then
    echo "Funding sikadev with 2500.0000 CGHS for wallet testing..."
    if [[ -f "${ROOT}/wallet/.password" ]]; then
      DEV_PW="$(tr -d '\n' < "${ROOT}/wallet/.password")"
      "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet unlock --password "${DEV_PW}" 2>/dev/null || true
    fi
    if "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" push action sika.token issue '["sikadev","2500.0000 CGHS","SikaChainDev bootstrap"]' -p sika.issue@active; then
      echo "  funded sikadev with CGHS"
    else
      echo "  (CGHS issue failed — run deploy-sika-system.sh to create CGHS on sika.token)"
    fi
  fi
fi

echo ""
if is_sika_token_ready; then
  bash "${SCRIPT_DIR}/ensure-system-abi.sh" 2>/dev/null || echo "  (ensure-system-abi skipped — chain offline?)"
  bash "${SCRIPT_DIR}/create-dev-accounts.sh" 2>/dev/null || echo "  (create-dev-accounts skipped — see create-dev-accounts.sh)"
  bash "${SCRIPT_DIR}/setup-biz-msig-dev.sh" 2>/dev/null || echo "  (setup-biz-msig-dev skipped — see setup-biz-msig-dev.sh)"
fi

echo ""
if [[ "${SKIP_HYPERION:-0}" != "1" ]] && command -v docker >/dev/null 2>&1; then
  echo "Starting Hyperion backing services (Elasticsearch, MongoDB, Redis, RabbitMQ)..."
  bash "${SCRIPT_DIR}/start-hyperion-deps.sh" 2>/dev/null || echo "  (Hyperion deps skipped — install Docker or set SKIP_HYPERION=1)"
  node "${SCRIPT_DIR}/sync-app-env.mjs" 2>/dev/null || true
  if [[ "${START_HYPERION:-0}" == "1" ]]; then
    echo "Starting Hyperion indexer (START_HYPERION=1)..."
    bash "${SCRIPT_DIR}/start-hyperion.sh" 2>/dev/null || echo "  (start-hyperion failed — run manually after SHIP is enabled)"
  fi
  if bash "${SCRIPT_DIR}/check-hyperion.sh" 2>/dev/null; then
    echo "Hyperion indexer is reachable — wallet activity/history ready"
  else
    echo "Hyperion not indexed yet — run: bash scripts/start-hyperion.sh"
    echo "  Then: bash scripts/wallet-ready.sh"
  fi
fi

echo ""
bash "${SCRIPT_DIR}/status.sh"

echo ""
echo "Next:"
echo "  Wallet-ready: bash scripts/wallet-ready.sh   (RPC + Hyperion + dev accounts)"
echo "  Bindings: bash scripts/generate-bindings.sh  (or npm run contracts:generate in Sika app)"
echo "  Msig:     bash scripts/deploy-msig.sh        (${MSIG_ACCOUNT:-sika.msig})"
echo "  Biz MSIG: bash scripts/setup-biz-msig-dev.sh (sikamsig1 — import-from-chain E2E)"
echo "  NFTs:     bash scripts/mint-nft-dev.sh        (after deploy-atomicassets.sh)"
echo "  Hyperion: bash scripts/start-hyperion-deps.sh && START_HYPERION=1 bash scripts/bootstrap-dev.sh"
echo "            or: bash scripts/start-hyperion.sh"
echo "  App:  cp \"Sika app/.env.sikachaindev\" \"Sika app/.env.local\" && cd \"Sika app\" && npm run dev"
echo "  API:  cd \"wharfkit adapter\" && cp .env.example .env && npm run dev"
