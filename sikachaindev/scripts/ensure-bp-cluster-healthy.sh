#!/usr/bin/env bash
# Detect a stalled multinode cluster and attempt recovery.
#
# Usage:
#   bash scripts/ensure-bp-cluster-healthy.sh          # exit 0 when advancing
#   ENSURE_BP_RECONFIGURE=1 bash scripts/ensure-bp-cluster-healthy.sh  # reconfigure if resume fails
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

HTTP_BASE=8888
WAIT_SEC="${ENSURE_BP_WAIT_SEC:-3}"
RECONFIGURE="${ENSURE_BP_RECONFIGURE:-1}"

head_block_num() {
  curl -sf "${NODE_URL}/v1/chain/get_info" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['head_block_num'])"
}

chain_advancing() {
  local before after
  before="$(head_block_num)"
  sleep "${WAIT_SEC}"
  after="$(head_block_num)"
  [[ "${after}" -gt "${before}" ]]
}

lib_lag() {
  curl -sf "${NODE_URL}/v1/chain/get_info" \
    | python3 -c "import json,sys; i=json.load(sys.stdin); print(i['head_block_num']-i['last_irreversible_block_num'])"
}

resume_all_producers() {
  local idx port count
  count="$(multinode_node_count)"
  for ((idx = 1; idx <= count; idx++)); do
    port=$((HTTP_BASE + idx - 1))
    curl -sf -X POST "http://127.0.0.1:${port}/v1/producer/resume" -d '{}' >/dev/null 2>&1 || true
  done
}

if ! is_multinode_cluster; then
  exit 0
fi

if chain_advancing; then
  exit 0
fi

echo "=== ensure-bp-cluster-healthy ==="
lag="$(lib_lag)"
echo "  multinode chain stalled at block $(head_block_num) (head-lib gap ${lag}) — resuming producers..."

resume_all_producers
sleep "${WAIT_SEC}"

if chain_advancing; then
  echo "OK: chain advancing after producer resume"
  exit 0
fi

if [[ "${RECONFIGURE}" != "1" ]]; then
  echo "FAIL: chain still stalled (set ENSURE_BP_RECONFIGURE=1 to reconfigure)" >&2
  exit 1
fi

echo "  resume did not help — reconfiguring cluster..."
bash "${SCRIPT_DIR}/reconfigure-6bp-cluster.sh" >/dev/null

sleep "${WAIT_SEC}"
if chain_advancing; then
  echo "OK: chain advancing after reconfigure"
  exit 0
fi

if [[ "${ENSURE_BP_REFRESH:-1}" == "1" ]]; then
  echo "  reconfigure did not help — refreshing multinode chain clones..."
  bash "${SCRIPT_DIR}/stop-bp-cluster.sh" >/dev/null 2>&1 || true
  BP_CLUSTER_REFRESH=1 bash "${SCRIPT_DIR}/start-6bp-cluster.sh" >/dev/null
  sleep "${WAIT_SEC}"
  if chain_advancing; then
    echo "OK: chain advancing after cluster refresh"
    exit 0
  fi
fi

echo "FAIL: multinode chain still stalled after reconfigure" >&2
exit 1
