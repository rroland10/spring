#!/usr/bin/env bash
# Generate Hyperion config for SikaChainDev and print install steps.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HYPERION_DIR="${HYPERION_DIR:-${ROOT}/hyperion/hyperion-history-api}"

node "${SCRIPT_DIR}/hyperion-gen-config.mjs"
node "${SCRIPT_DIR}/configure-hyperion-dev.mjs" 2>/dev/null || true

echo ""
echo "=== Hyperion setup (SikaChainDev) ==="
echo ""
echo "1. Start backing services (if not running):"
echo "     bash scripts/start-hyperion-deps.sh"
echo ""
echo "2. Restart nodeos with SHIP:"
echo "     ENABLE_SHIP=1 bash scripts/stop-all.sh && ENABLE_SHIP=1 bash scripts/start-all.sh"
echo ""
echo "3. Clone Hyperion (once):"
if [[ ! -d "${HYPERION_DIR}/package.json" ]]; then
  echo "     git clone --depth 1 --branch main https://github.com/eosrio/hyperion-history-api \"${HYPERION_DIR}\""
else
  echo "     (found ${HYPERION_DIR})"
fi
echo ""
echo "4. Follow https://hyperion.docs.eosrio.io/providers/install/manual_install/"
echo "   Use connection entry: hyperion/generated/connections.sikachaindev.json"
echo ""
echo "5. When API listens on :7001 (macOS: 7000 is used by AirPlay), update chain.json and app env:"
echo "     \"hyperionUrl\": \"http://127.0.0.1:7001\""
echo "     node scripts/sync-app-env.mjs --local"
echo "     bash scripts/check-hyperion.sh"
