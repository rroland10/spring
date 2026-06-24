#!/usr/bin/env bash
# Start N nodeos producer instances for real schedule rotation (default: 6).
#
# Prerequisites:
#   - Chain bootstrapped (bootstrap-dev.sh)
#   - Producers registered (bootstrap-21bp.sh or bootstrap-6bp.sh)
#   - Votes aligned to N producers (vote-bp-schedule.sh)
#
# Usage:
#   bash scripts/start-6bp-cluster.sh
#   BP_CLUSTER_SIZE=6 bash scripts/start-bp-cluster.sh
#   BP_CLUSTER_SIZE=21 PRODUCERS_JSON=config/producers-21.json bash scripts/start-bp-cluster.sh
#
# RPC stays on http://127.0.0.1:8888 (first producer node). P2P ports 9876+.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

BP_CLUSTER_SIZE="${BP_CLUSTER_SIZE:-6}"
PRODUCERS_JSON="${PRODUCERS_JSON:-${ROOT}/config/producers-${BP_CLUSTER_SIZE}.json}"
GENESIS="${ROOT}/config/genesis.json"
MULTINODE="${ROOT}/data/multinode"
SOURCE_DATA="${ROOT}/data"
NUM="${BP_CLUSTER_SIZE}"
HTTP_BASE=8888
P2P_BASE=9876

cleos_cmd() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" "$@"
}

if [[ ! -f "${PRODUCERS_JSON}" ]]; then
  echo "error: missing ${PRODUCERS_JSON}"
  exit 1
fi

if ! command -v "${NODEOS}" >/dev/null 2>&1 && [[ ! -x "${NODEOS}" ]]; then
  echo "error: nodeos not found"
  exit 1
fi

FIRST_BP="$(python3 -c "import json; print(json.load(open('${PRODUCERS_JSON}'))['producers'][0]['name'])")"

echo "=== SikaChainDev — start ${NUM}-BP cluster ==="

if [[ "${BP_RECONFIG_ONLY:-0}" == "1" ]]; then
  echo "Mode: reconfigure only (skip vote + chain clone)"
elif ! curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null 2>&1; then
  if [[ -f "${SOURCE_DATA}/blocks/blocks.log" ]]; then
    echo "RPC down — starting single node for vote sync..."
    bash "${SCRIPT_DIR}/write-lite-producer-config.sh"
    bash "${SCRIPT_DIR}/start-node.sh" --daemon
    bash "${SCRIPT_DIR}/wait-for-rpc.sh" 180
  else
    echo "error: chain not running — run bootstrap-dev.sh first"
    exit 1
  fi
fi

if [[ "${BP_RECONFIG_ONLY:-0}" != "1" ]]; then
  if ! cleos_cmd get table "${SIKA_SYSTEM_ACCOUNT}" "${SIKA_SYSTEM_ACCOUNT}" producers -l 5 2>/dev/null | grep -q "${FIRST_BP}"; then
    echo "error: ${FIRST_BP} not registered — run bootstrap-21bp.sh first"
    exit 1
  fi
fi

if [[ "${BP_SKIP_VOTE:-0}" != "1" && "${BP_RECONFIG_ONLY:-0}" != "1" ]]; then
  echo "Aligning votes to ${NUM} producers..."
  BP_CLUSTER_SIZE="${NUM}" PRODUCERS_JSON="${PRODUCERS_JSON}" VOTERS_JSON="${PRODUCERS_JSON}" \
    bash "${SCRIPT_DIR}/vote-bp-schedule.sh"
  BP_CLUSTER_SIZE="${NUM}" PRODUCERS_JSON="${PRODUCERS_JSON}" ENSURE_WAIT=0 bash "${SCRIPT_DIR}/ensure-producer-schedule.sh"
fi

echo "Stopping single-node nodeos..."
bash "${SCRIPT_DIR}/stop-node.sh" 2>/dev/null || true
sleep 1

if [[ "${BP_RECONFIG_ONLY:-0}" == "1" ]]; then
  echo "Reconfiguring ${NUM} multinode producers (no chain clone)..."
elif [[ ! -d "${SOURCE_DATA}/blocks" ]]; then
  echo "error: no blockchain data at ${SOURCE_DATA} — bootstrap the chain first"
  exit 1
fi

mkdir -p "${MULTINODE}"

sync_node_data() {
  local idx="$1"
  local dest="${MULTINODE}/node${idx}/data"
  local src_log="${SOURCE_DATA}/blocks/blocks.log"
  local dest_log="${dest}/blocks/blocks.log"

  if [[ "${BP_CLUSTER_REFRESH:-0}" == "1" ]] && [[ -d "${dest}" ]]; then
    echo "  refreshing node${idx} chain state"
    rm -rf "${dest}"
  fi

  if [[ -f "${dest_log}" ]] && [[ -f "${src_log}" ]]; then
    local src_size dest_size
    src_size="$(stat -f%z "${src_log}" 2>/dev/null || echo 0)"
    dest_size="$(stat -f%z "${dest_log}" 2>/dev/null || echo 0)"
    # Skip re-clone when destination looks like a current copy of source chain data.
    if [[ "${dest_size}" -gt 1000000 ]] && [[ "${dest_size}" -ge $(( src_size * 85 / 100 )) ]]; then
      return 0
    fi
    echo "  stale/incomplete clone at node${idx} (${dest_size} vs ${src_size} bytes) — re-cloning"
    rm -rf "${dest}"
  fi

  if [[ -f "${dest_log}" ]]; then
    return 0
  fi
  echo "  cloning chain state → node${idx}"
  mkdir -p "${dest}"
  local clone_src="${SOURCE_DATA}"
  local node1_log="${MULTINODE}/node1/data/blocks/blocks.log"
  if [[ "${idx}" -gt 1 ]] && [[ -f "${node1_log}" ]]; then
    local node1_size
    node1_size="$(stat -f%z "${node1_log}" 2>/dev/null || echo 0)"
    if [[ "${node1_size}" -gt 1000000 ]]; then
      clone_src="${MULTINODE}/node1/data"
      echo "  (from node1 snapshot)"
    fi
  fi
  rsync -a --delete \
    --exclude multinode/ \
    --exclude state-history/ \
    --exclude nodeos.pid --exclude nodeos.log --exclude 'nodeos*.log' \
    --exclude .clean_shutdown --exclude '*.log' \
    "${clone_src}/" "${dest}/"
  # Force replay on first start — cloned state may be dirty after abrupt single-node stop.
  rm -f "${dest}/.clean_shutdown"
}

write_config() {
  local idx="$1" name="$2" pub="$3" pvt="$4"
  local http_port=$((HTTP_BASE + idx - 1))
  local p2p_port=$((P2P_BASE + idx - 1))
  local cfg_dir="${MULTINODE}/node${idx}/config"
  mkdir -p "${cfg_dir}"

  {
    # Only node1 stale-fallback: avoids fork wars while keeping the chain alive if a BP misses a slot.
    if [[ "${idx}" -eq 1 && "${BP_DEV_STALE:-1}" == "1" ]]; then
      echo "enable-stale-production = true"
    else
      echo "enable-stale-production = false"
    fi
    echo "production-pause-vote-timeout-ms = 0"
    echo "producer-name = ${name}"
    echo "signature-provider = ${pub}=KEY:${pvt}"
    if [[ "${idx}" -eq 1 ]] && [[ "${ENABLE_SHIP:-1}" == "1" ]]; then
      echo "http-server-address = 0.0.0.0:${http_port}"
    else
      echo "http-server-address = 127.0.0.1:${http_port}"
    fi
    echo "p2p-listen-endpoint = 127.0.0.1:${p2p_port}"
    echo "p2p-server-address = 127.0.0.1:${p2p_port}"
    # Same-host multinode: default max-nodes-per-host=1 prevents a full producer mesh.
    echo "p2p-max-nodes-per-host = ${BP_P2P_MAX_PER_HOST:-16}"
    echo "max-clients = ${BP_MAX_CLIENTS:-25}"
    echo "max-reversible-blocks = ${BP_MAX_REVERSIBLE_BLOCKS:-20000}"
    echo "max-irreversible-block-age = ${BP_MAX_IRREVERSIBLE_AGE:--1}"
    echo "agent-name = sikachaindev-node${idx}"
    local peer
    # Unidirectional mesh (lower index only) avoids duplicate go_away on localhost.
    for peer in $(seq 1 $((idx - 1))); do
      echo "p2p-peer-address = 127.0.0.1:$((P2P_BASE + peer - 1))"
    done
    echo "plugin = eosio::chain_plugin"
    echo "plugin = eosio::producer_plugin"
    echo "plugin = eosio::http_plugin"
    echo "plugin = eosio::net_plugin"
    echo "plugin = eosio::chain_api_plugin"
    echo "plugin = eosio::producer_api_plugin"
    echo "plugin = eosio::net_api_plugin"
    echo "contracts-console = true"
    echo "resource-monitor-not-shutdown-on-threshold-exceeded = true"
    if [[ "${idx}" -eq 1 ]]; then
      echo "access-control-allow-origin = *"
      echo "access-control-allow-headers = Content-Type,Accept,Authorization,X-Requested-With"
      echo "access-control-allow-credentials = true"
      echo "http-validate-host = false"
      if [[ "${ENABLE_SHIP:-1}" == "1" ]]; then
        echo "plugin = eosio::state_history_plugin"
        echo "disable-replay-opts = true"
        echo "chain-state-history = true"
        echo "trace-history = true"
        echo "state-history-endpoint = 0.0.0.0:8080"
      fi
    fi
  } > "${cfg_dir}/config.ini"
}

start_node() {
  local idx="$1"
  local data_dir="${MULTINODE}/node${idx}/data"
  local cfg_dir="${MULTINODE}/node${idx}/config"
  local log="${MULTINODE}/node${idx}/nodeos.log"
  local pid_file="${MULTINODE}/node${idx}/nodeos.pid"

  if [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; then
    echo "  node${idx} already running (pid $(cat "${pid_file}"))"
    return 0
  fi

  local args=(
    --config-dir "${cfg_dir}"
    --data-dir "${data_dir}"
    --genesis-json "${GENESIS}"
  )
  if [[ -f "${data_dir}/blocks/blocks.log" ]] && [[ ! -f "${data_dir}/.clean_shutdown" ]]; then
    args+=(--replay-blockchain)
    echo "  node${idx}: replay required (unclean state)"
  fi

  local pid
  pid="$(bash "${SCRIPT_DIR}/daemonize.sh" "${log}" "${NODEOS}" "${args[@]}")"
  echo "${pid}" > "${pid_file}"
  echo "  started node${idx} (pid ${pid}, http $((HTTP_BASE + idx - 1)))"
}

echo "Preparing ${NUM} node directories..."
idx=0
while IFS=$'\t' read -r name pub pvt; do
  idx=$((idx + 1))
  if [[ "${BP_RECONFIG_ONLY:-0}" != "1" ]]; then
    sync_node_data "${idx}"
  fi
  write_config "${idx}" "${name}" "${pub}" "${pvt}"
done < <(python3 - <<'PY' "${PRODUCERS_JSON}"
import json, sys
for p in json.load(open(sys.argv[1]))["producers"]:
    print(f"{p['name']}\t{p['pub']}\t{p['pvt']}")
PY
)

echo "Starting producer nodes (node1 first, then peers)..."
idx=0
while IFS=$'\t' read -r name _pub _pvt; do
  idx=$((idx + 1))
  start_node "${idx}"
  if [[ "${idx}" -eq 1 ]]; then
    echo "Waiting for RPC on ${NODE_URL} (node1)..."
    for _ in $(seq 1 120); do
      if curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
  else
    sleep 1
  fi
done < <(python3 - <<'PY' "${PRODUCERS_JSON}"
import json, sys
for p in json.load(open(sys.argv[1]))["producers"]:
    print(f"{p['name']}\t{p['pub']}\t{p['pvt']}")
PY
)

echo "Resuming block production on all nodes..."
idx=0
while IFS=$'\t' read -r _name _pub _pvt; do
  idx=$((idx + 1))
  port=$((HTTP_BASE + idx - 1))
  curl -sf -X POST "http://127.0.0.1:${port}/v1/producer/resume" -d '{}' >/dev/null 2>&1 \
    && echo "  resumed node${idx} (:${port})" \
    || echo "  note: resume skipped for node${idx} (:${port})"
done < <(python3 - <<'PY' "${PRODUCERS_JSON}"
import json, sys
for p in json.load(open(sys.argv[1]))["producers"]:
    print(f"{p['name']}\t{p['pub']}\t{p['pvt']}")
PY
)

echo ""
if curl -sf "${NODE_URL}/v1/chain/get_info" >/dev/null 2>&1; then
  cleos_cmd get info | head -5 || true
  echo ""
  echo "${NUM}-BP cluster running. RPC: ${NODE_URL} (${FIRST_BP})"
  echo "Stop: bash scripts/stop-bp-cluster.sh"
else
  echo "warning: RPC not ready yet — check logs under ${MULTINODE}/node*/nodeos.log"
fi
