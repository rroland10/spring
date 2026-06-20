#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
"${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
