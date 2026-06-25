#!/usr/bin/env bash
# Bring Hyperion deps + indexer back after Docker restart or ES outage.
#
# Usage:
#   bash scripts/hyperion-recover.sh
#   ENABLE_SHIP=1 bash scripts/hyperion-recover.sh   # also ensure SHIP on nodeos
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"
# shellcheck source=lib/docker-ready.sh
source "${SCRIPT_DIR}/lib/docker-ready.sh"

echo "=== Hyperion recover ==="

if [[ "${OPEN_DOCKER:-1}" == "1" ]] && ! DOCKER_READY_TIMEOUT=5 docker_ready 2>/dev/null; then
  echo "Opening Docker Desktop..."
  open -a Docker 2>/dev/null || true
  echo "Waiting for Docker daemon (up to ${DOCKER_START_WAIT:-90}s)..."
  ready=0
  for _ in $(seq 1 "${DOCKER_START_WAIT:-90}"); do
    if DOCKER_READY_TIMEOUT=3 docker_ready 2>/dev/null; then
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "${ready}" -eq 0 ]]; then
    echo "error: Docker did not become ready — quit Docker Desktop fully, reopen, then re-run" >&2
    bash "${SCRIPT_DIR}/docker-diagnose.sh" || true
    exit 1
  fi
fi

if ! docker_ready; then
  bash "${SCRIPT_DIR}/docker-diagnose.sh" || true
  exit 1
fi

if ! bash "${SCRIPT_DIR}/check-ship.sh" >/dev/null 2>&1; then
  if [[ "${RESTART_NODEOS_FOR_SHIP:-0}" == "1" ]]; then
    echo "Ensuring SHIP on nodeos (restart)..."
    ENABLE_SHIP=1 bash "${SCRIPT_DIR}/restart-ship.sh"
  else
    echo "error: SHIP not listening — Hyperion needs ws://127.0.0.1:8080" >&2
    echo "  ENABLE_SHIP=1 bash scripts/start-all.sh && bash scripts/wait-for-rpc.sh" >&2
    echo "  Or: RESTART_NODEOS_FOR_SHIP=1 bash scripts/hyperion-recover.sh" >&2
    exit 1
  fi
fi

bash "${SCRIPT_DIR}/start-hyperion-deps.sh"

if ! curl -sf http://127.0.0.1:9200/_cluster/health >/dev/null 2>&1; then
  echo "error: Elasticsearch still down after deps start" >&2
  exit 1
fi

node "${SCRIPT_DIR}/configure-hyperion-dev.mjs" --docker
bash "${SCRIPT_DIR}/start-hyperion.sh"

echo ""
echo "Waiting for get_actions..."
for _ in $(seq 1 36); do
  if bash "${SCRIPT_DIR}/check-hyperion.sh" >/dev/null 2>&1; then
    bash "${SCRIPT_DIR}/check-hyperion.sh"
    echo "=== Hyperion recover complete ==="
    exit 0
  fi
  sleep 5
done

echo "error: Hyperion API up but get_actions not ready — check indexer logs:" >&2
echo "  docker logs sikachaindev-hyperion-indexer --tail 50" >&2
exit 1
