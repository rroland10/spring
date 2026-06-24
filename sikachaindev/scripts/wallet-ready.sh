#!/usr/bin/env bash
# Wallet-ready: RPC + dev accounts + Hyperion (required for activity/history UX).
# Optionally probes GTM explorer; set CHECK_GTM=1 to fail when marketing site is down.
#
# Usage:
#   bash scripts/wallet-ready.sh
#   WALLET_READY=1 bash scripts/check-health.sh   # same Hyperion gate
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

export WALLET_READY=1

echo "=== SikaChainDev wallet-ready ==="
echo "  RPC=${NODE_URL}"
echo ""

bash "${SCRIPT_DIR}/wait-for-rpc.sh" 60
bash "${SCRIPT_DIR}/check-health.sh"
bash "${SCRIPT_DIR}/check-hyperion.sh"

if [[ "${CHECK_GTM:-0}" == "1" ]]; then
  bash "${SCRIPT_DIR}/check-gtm.sh"
else
  CHECK_GTM=0 bash "${SCRIPT_DIR}/check-gtm.sh" || true
fi

echo ""
echo "=== wallet-ready complete ==="
echo "  Wallet:  ${SIKA_APP_URL}/app/home"
echo "  Install: open in Safari/Chrome → Add to Home Screen (see Sika app README)"
