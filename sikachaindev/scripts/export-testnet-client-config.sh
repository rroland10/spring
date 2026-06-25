#!/usr/bin/env bash
# Export Anchor + wallet env for a live testnet from RPC (local docker or hosted).
#
# Usage:
#   NODE_URL=http://127.0.0.1:18890 bash scripts/export-testnet-client-config.sh
#   NODE_URL=https://rpc.testnet.sikachain.gh \
#     TESTNET_HYPERION_URL=https://hyperion.testnet.sikachain.gh \
#     bash scripts/export-testnet-client-config.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT}/config/testnet/generated/client-export}"
NODE_URL="${NODE_URL:?set NODE_URL}"

mkdir -p "${OUT_DIR}"

chain_id="$(curl -sf "${NODE_URL}/v1/chain/get_info" | python3 -c 'import json,sys; print(json.load(sys.stdin)["chain_id"])')"
rpc="${TESTNET_RPC_URL:-${NODE_URL}}"
hyperion="${TESTNET_HYPERION_URL:-${HYPERION_URL:-}}"

echo "=== export-testnet-client-config ==="
echo "  chain_id=${chain_id}"
echo "  RPC=${rpc}"
echo "  HYPERION=${hyperion:-<unset>}"
echo ""

TESTNET_CHAIN_ID="${chain_id}" \
TESTNET_RPC_URL="${rpc}" \
TESTNET_HYPERION_URL="${hyperion}" \
TESTNET_CHAIN_NAME="${TESTNET_CHAIN_NAME:-SikaChain Testnet}" \
  node "${SCRIPT_DIR}/export-anchor-chain.mjs" --testnet-example "${OUT_DIR}/anchor-chain.json"

TESTNET_CHAIN_ID="${chain_id}" \
TESTNET_RPC_URL="${rpc}" \
TESTNET_HYPERION_URL="${hyperion}" \
TESTNET_APP_URL="${TESTNET_APP_URL:-https://app.sikachain.gh}" \
TESTNET_SITE_URL="${TESTNET_SITE_URL:-https://sikachain.com}" \
  node "${SCRIPT_DIR}/export-testnet-env.mjs" "${OUT_DIR}/sika-app.env"

cat > "${OUT_DIR}/README.txt" <<EOF
SikaChain testnet client export
  chain_id: ${chain_id}
  RPC:        ${rpc}
  Hyperion:   ${hyperion:-none}

Files:
  anchor-chain.json  — Anchor Settings → Blockchains → Add (import JSON)
  sika-app.env       — hosting env for Sika app (no DEV_WALLET)

Verify hosted stack:
  NODE_URL=${rpc} EXPECT_CHAIN_ID=${chain_id} \\
    HYPERION_URL=${hyperion:-https://hyperion.testnet.sikachain.gh} \\
    bash scripts/verify-predeploy-remote.sh
EOF

echo "Wrote ${OUT_DIR}/"
ls -la "${OUT_DIR}"
