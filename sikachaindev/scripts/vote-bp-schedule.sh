#!/usr/bin/env bash
# Point all producer votes at the active BP cluster set (default: 6 producers).
#
# Usage:
#   BP_CLUSTER_SIZE=6 bash scripts/vote-bp-schedule.sh
#   PRODUCERS_JSON=config/producers-6.json bash scripts/vote-bp-schedule.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

BP_CLUSTER_SIZE="${BP_CLUSTER_SIZE:-6}"
SCHEDULE_JSON="${PRODUCERS_JSON:-${ROOT}/config/producers-${BP_CLUSTER_SIZE}.json}"
VOTERS_JSON="${VOTERS_JSON:-${SCHEDULE_JSON}}"

if [[ ! -f "${SCHEDULE_JSON}" ]]; then
  echo "error: missing ${SCHEDULE_JSON}"
  exit 1
fi

cleos_cmd() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

unlock_wallet() {
  if [[ -f "${ROOT}/wallet/.password" ]]; then
    cleos_cmd wallet open 2>/dev/null || true
    cleos_cmd wallet unlock --password "$(tr -d '\n' < "${ROOT}/wallet/.password")" 2>/dev/null || true
  fi
}

retry() { local n=0; until "$@" || [[ $((n+=1)) -ge 8 ]]; do sleep 1; done }

unlock_wallet

SCHEDULE=()
while IFS= read -r n; do
  SCHEDULE+=("${n}")
done < <(python3 - <<'PY' "${SCHEDULE_JSON}"
import json, sys
for p in json.load(open(sys.argv[1]))["producers"]:
    print(p["name"])
PY
)

VOTERS=()
while IFS= read -r n; do
  VOTERS+=("${n}")
done < <(python3 - <<'PY' "${VOTERS_JSON}"
import json, sys
for p in json.load(open(sys.argv[1]))["producers"]:
    print(p["name"])
PY
)

echo "=== vote-bp-schedule (${#SCHEDULE[@]} producers) ==="
echo "  schedule: ${SCHEDULE[*]}"
echo ""

for voter in "${VOTERS[@]}"; do
  echo "  voting ${voter} → ${SCHEDULE[*]}"
  retry cleos_cmd -r 1h system voteproducer prods "${voter}" "${SCHEDULE[@]}" -p "${voter}@active"
done

echo ""
echo "Active producer schedule:"
cleos_cmd system listproducers -l "${BP_CLUSTER_SIZE}" || true
echo ""
echo "=== vote-bp-schedule complete ==="
