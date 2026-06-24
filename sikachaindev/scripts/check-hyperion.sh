#!/usr/bin/env bash
# Exit 0 when Hyperion v2 responds for SikaChainDev (optional indexer).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

HYPERION_URL="${HYPERION_URL:-$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json')).get('hyperionUrl','') or 'http://127.0.0.1:7001')" 2>/dev/null)}"
CHAIN_ID="${CHAIN_ID:-$(python3 -c "import json; print(json.load(open('${ROOT}/chain.json'))['chainId'])" 2>/dev/null)}"

if [[ -z "${HYPERION_URL}" ]]; then
  if [[ "${WALLET_READY:-0}" == "1" ]]; then
    echo "FAIL: hyperionUrl not set in chain.json (required for wallet activity)"
    exit 1
  fi
  echo "SKIP: hyperionUrl not set in chain.json (see docs/hyperion-dev.md)"
  exit 0
fi

HYPERION_URL="${HYPERION_URL%/}"
echo "=== Hyperion check (${HYPERION_URL}) ==="

FAIL=0
if curl -sf "${HYPERION_URL}/v2/health" >/dev/null 2>&1; then
  echo "  ok  /v2/health"
else
  echo "  FAIL /v2/health"
  FAIL=1
fi

PROBE_ACCOUNT="${HYPERION_PROBE_ACCOUNT:-${SIKA_SYSTEM_ACCOUNT}}"

if curl -sf "${HYPERION_URL}/v2/history/get_actions?account=${PROBE_ACCOUNT}&limit=1" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if 'actions' in d else 1)" 2>/dev/null; then
  echo "  ok  get_actions (${PROBE_ACCOUNT})"
else
  echo "  FAIL get_actions"
  FAIL=1
fi

exit "${FAIL}"
