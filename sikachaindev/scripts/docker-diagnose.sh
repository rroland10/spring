#!/usr/bin/env bash
# Quick Docker + Hyperion diagnostics (non-destructive).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/docker-ready.sh"

echo "=== Docker / Hyperion diagnose ==="

if command -v docker >/dev/null 2>&1; then
  if DOCKER_READY_TIMEOUT=15 docker_ready; then
    echo "  ok  Docker daemon"
    docker compose -f "${SCRIPT_DIR}/../hyperion/docker-compose.yml" ps 2>/dev/null | head -8 || true
  else
    echo "  FAIL Docker daemon (not responding)"
    stuck="$(pgrep -fl 'docker compose.*hyperion' 2>/dev/null || true)"
    if [[ -n "${stuck}" ]]; then
      echo "  hint: stuck compose process — kill and restart Docker Desktop:"
      echo "    pkill -f 'docker compose.*hyperion' || true"
    fi
    echo "  hint: quit Docker Desktop fully, reopen, wait until: docker ps"
  fi
else
  echo "  FAIL docker CLI not installed"
fi

echo ""
curl -sf --max-time 3 http://127.0.0.1:9200/_cluster/health >/dev/null \
  && echo "  ok  Elasticsearch :9200" \
  || echo "  --  Elasticsearch :9200 (down)"

curl -sf --max-time 3 http://127.0.0.1:7001/v2/health >/dev/null \
  && echo "  ok  Hyperion API :7001" \
  || echo "  --  Hyperion API :7001 (down)"

if bash "${SCRIPT_DIR}/check-ship.sh" >/dev/null 2>&1; then
  echo "  ok  SHIP :8080"
else
  echo "  --  SHIP :8080 — ENABLE_SHIP=1 bash scripts/restart-ship.sh"
fi

echo ""
echo "Recover when Docker is healthy:"
echo "  bash scripts/hyperion-recover.sh"
