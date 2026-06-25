#!/usr/bin/env bash
# Wait for sika.system onblock() to promote voted BPs into the pending/active
# producer schedule (requires sika.system with update_elected_producers).
#
# Usage:
#   BP_CLUSTER_SIZE=6 bash scripts/ensure-producer-schedule.sh
#   ENSURE_WAIT=0 bash scripts/ensure-producer-schedule.sh   # skip wait
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

BP_CLUSTER_SIZE="${BP_CLUSTER_SIZE:-6}"
SCHEDULE_JSON="${PRODUCERS_JSON:-${ROOT}/config/producers-${BP_CLUSTER_SIZE}.json}"
ENSURE_WAIT="${ENSURE_WAIT:-1}"
WAIT_SECS="${ENSURE_WAIT_SECS:-70}"

cleos_cmd() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

read_global() {
  cleos_cmd get table "${SIKA_SYSTEM_ACCOUNT}" "${SIKA_SYSTEM_ACCOUNT}" global -l 1 2>/dev/null \
    | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['rows'][0]))"
}

schedule_names() {
  curl -sf "${NODE_URL}/v1/chain/get_producer_schedule" | python3 -c "
import json, sys
s = json.load(sys.stdin)
for label in ('active', 'pending'):
    ps = s.get(label, {})
    names = [p['producer_name'] for p in ps.get('producers', [])]
    print(f\"{label}:\" + (','.join(names) if names else ''))
"
}

echo "=== ensure-producer-schedule ==="
echo "  RPC:      ${NODE_URL}"
echo "  cluster:  ${BP_CLUSTER_SIZE} producers"
echo ""

if [[ ! -f "${SCHEDULE_JSON}" ]]; then
  echo "error: missing ${SCHEDULE_JSON}"
  exit 1
fi

if ! curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null 2>&1; then
  echo "error: nodeos not running at ${NODE_URL}"
  exit 1
fi

EXPECTED=()
while IFS= read -r n; do EXPECTED+=("${n}"); done < <(python3 - <<'PY' "${SCHEDULE_JSON}"
import json, sys
for p in json.load(open(sys.argv[1]))["producers"]:
    print(p["name"])
PY
)

GLOBAL="$(read_global)"
BEFORE="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['last_producer_schedule_update'])" "${GLOBAL}")"
SIZE="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['last_producer_schedule_size'])" "${GLOBAL}")"
echo "  last_producer_schedule_update: ${BEFORE}"
echo "  last_producer_schedule_size:  ${SIZE}"

if [[ "${ENSURE_WAIT}" == "1" ]] && [[ "${SIZE}" == "0" ]]; then
  echo ""
  echo "Waiting ${WAIT_SECS}s for onblock schedule promotion..."
  sleep "${WAIT_SECS}"
  GLOBAL="$(read_global)"
  AFTER="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['last_producer_schedule_update'])" "${GLOBAL}")"
  SIZE="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['last_producer_schedule_size'])" "${GLOBAL}")"
  echo "  last_producer_schedule_update: ${BEFORE} → ${AFTER}"
  echo "  last_producer_schedule_size:  ${SIZE}"
fi

echo ""
schedule_names | while IFS= read -r line; do echo "  ${line}"; done

PENDING_OK=0
if curl -sf "${NODE_URL}/v1/chain/get_producer_schedule" | python3 -c "
import json, sys
expected = set(sys.argv[1:])
s = json.load(sys.stdin)
pending = {p['producer_name'] for p in s.get('pending', {}).get('producers', [])}
active = {p['producer_name'] for p in s.get('active', {}).get('producers', [])}
sys.exit(0 if expected <= pending or expected <= active else 1)
" "${EXPECTED[@]}"; then
  PENDING_OK=1
fi

if [[ "${PENDING_OK}" -eq 0 ]]; then
  echo ""
  echo "warning: expected BPs not yet in pending/active schedule."
  echo "  Ensure sika.system WASM includes update_elected_producers (upgrade-contracts.sh)."
  exit 1
fi

echo ""
echo "=== ensure-producer-schedule complete ==="
