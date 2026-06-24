#!/usr/bin/env bash
# Sync app, website, and adapter env from chain.json (Phase 3 aware).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

node "${SCRIPT_DIR}/sync-app-env.mjs" --local "$@"
node "${SCRIPT_DIR}/sync-adapter-env.mjs"
node "${SCRIPT_DIR}/export-anchor-chain.mjs"
node "${SCRIPT_DIR}/export-anchor-chain.mjs" --testnet-example

WEB_DIR="${SIKA_CHAIN_WEB_DIR:-/Users/randallroland/Desktop/Projects/SikaChain}"
if [[ -f "${WEB_DIR}/scripts/sync-chain-config.mjs" ]]; then
  node "${WEB_DIR}/scripts/sync-chain-config.mjs"
fi

echo "Dev env sync complete."
