#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_BIN="${ROOT}/../build/programs"
if [[ -z "${CLEOS:-}" ]]; then
  if [[ -x "${BUILD_BIN}/cleos/cleos" ]]; then
    CLEOS="${BUILD_BIN}/cleos/cleos"
  else
    CLEOS="cleos"
  fi
fi
NODE_URL="${NODE_URL:-http://127.0.0.1:8888}"

if ! command -v "${CLEOS}" >/dev/null 2>&1; then
  echo "error: cleos not found"
  exit 1
fi

"${CLEOS}" --url "${NODE_URL}" get info | python3 -c "
import json, sys
info = json.load(sys.stdin)
print('SikaChainDev')
print('  chain_id:', info['chain_id'])
print('  head_block:', info['head_block_num'])
print('  producer:', info.get('head_block_producer', 'n/a'))
"
