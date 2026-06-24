#!/usr/bin/env bash
# Ensure sika.system ABI exports delband (required for wallet stake queries on Phase 3).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

SYS="${SIKA_SYSTEM_ACCOUNT:-sika}"

delband_queryable() {
  curl -sf "${NODE_URL}/v1/chain/get_table_rows" \
    -H 'Content-Type: application/json' \
    -d "{\"json\":true,\"code\":\"${SYS}\",\"scope\":\"sikadev\",\"table\":\"delband\",\"limit\":1}" \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
if d.get('error') or d.get('code', 200) >= 400:
    sys.exit(1)
if 'rows' not in d:
    sys.exit(1)
"
}

if delband_queryable 2>/dev/null; then
  echo "  ok  sika.system ABI (delband queryable)"
  exit 0
fi

echo "Patching sika.system ABI (delband missing on ${SYS})..."
bash "${SCRIPT_DIR}/upgrade-system-abi.sh" --no-smoke
