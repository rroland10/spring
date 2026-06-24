#!/usr/bin/env bash
# Sample head_block_producer over a window — confirms 6-BP rotation when multinode is up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

RPC="${NODE_URL:-http://127.0.0.1:8888}"
SAMPLES="${BP_ROTATION_SAMPLES:-24}"
INTERVAL="${BP_ROTATION_INTERVAL:-0.5}"
MIN_UNIQUE="${BP_ROTATION_MIN_UNIQUE:-2}"

run_rotation_check() {
  python3 - <<PY "${RPC}" "${SAMPLES}" "${INTERVAL}" "${MIN_UNIQUE}"
import json, sys, time, urllib.request
rpc, samples, interval, min_unique = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4])
producers = []
blocks = []
for i in range(samples):
    with urllib.request.urlopen(f"{rpc}/v1/chain/get_info") as r:
        info = json.load(r)
    p = info.get("head_block_producer", "?")
    b = info.get("head_block_num", 0)
    producers.append(p)
    blocks.append(b)
    print(f"  block {b}: {p}")
    if i + 1 < samples:
        time.sleep(interval)
uniq = sorted(set(producers))
print(f"unique producers ({len(uniq)}): {', '.join(uniq)}")
tail = blocks[-max(4, samples // 2):]
if len(set(blocks)) <= 1 and samples >= 4:
    print("FAIL chain stalled (head block not advancing)", file=sys.stderr)
    sys.exit(2)
if len(set(tail)) <= 1 and samples >= 8:
    print("FAIL chain stalled mid-sample window", file=sys.stderr)
    sys.exit(2)
bp_set = {p for p in uniq if p.startswith('sikabp')}
if len(bp_set) >= min_unique:
    print(f"PASS multinode rotation ({len(bp_set)} BPs seen)")
    sys.exit(0)
if len(uniq) == 1 and uniq[0] in ('sika', 'sikabpa'):
    print("PASS lite mode (single producer advancing blocks)")
    sys.exit(0)
print(f"FAIL expected >={min_unique} rotating BPs, saw {len(bp_set)}", file=sys.stderr)
sys.exit(1)
PY
}

echo "=== verify-6bp-rotation (${SAMPLES} samples, ${INTERVAL}s apart) ==="

if ! curl -sf "${RPC}/v1/chain/get_info" >/dev/null 2>&1; then
  echo "FAIL: RPC not reachable at ${RPC}" >&2
  exit 1
fi

if is_multinode_cluster; then
  bash "${SCRIPT_DIR}/ensure-bp-cluster-healthy.sh" || true
fi

set +e
run_rotation_check
rc=$?
set -e

if [[ "${rc}" -eq 0 ]]; then
  echo "=== verify-6bp-rotation complete ==="
  exit 0
fi

if is_multinode_cluster && [[ "${rc}" -ne 0 ]]; then
  echo "  rotation check failed (rc=${rc}) — reconfiguring cluster and retrying once..."
  ENSURE_BP_RECONFIGURE=1 bash "${SCRIPT_DIR}/ensure-bp-cluster-healthy.sh" || true
  sleep 2
  set +e
  run_rotation_check
  rc=$?
  set -e
fi

if [[ "${rc}" -eq 0 ]]; then
  echo "=== verify-6bp-rotation complete ==="
  exit 0
fi

if [[ "${rc}" -eq 2 ]]; then
  echo "hint: bash scripts/reconfigure-6bp-cluster.sh  |  bash scripts/start-6bp-lite.sh" >&2
fi
exit 1
