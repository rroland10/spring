#!/usr/bin/env bash
# Start Elasticsearch, MongoDB, Redis, RabbitMQ for local Hyperion.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE="${ROOT}/hyperion/docker-compose.yml"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker not found — install Docker Desktop"
  exit 1
fi

# shellcheck source=lib/docker-ready.sh
source "${SCRIPT_DIR}/lib/docker-ready.sh"
docker_ready || exit 1

echo "=== Hyperion dependencies (docker compose) ==="
docker_compose_up -f "${COMPOSE}"

echo ""
echo "Waiting for Elasticsearch..."
ES_OK=0
for _ in $(seq 1 30); do
  if curl -sf http://127.0.0.1:9200/_cluster/health >/dev/null 2>&1; then
    echo "  ok  elasticsearch :9200"
    ES_OK=1
    break
  fi
  sleep 2
done
if [[ "${ES_OK}" -eq 0 ]]; then
  echo "  FAIL elasticsearch :9200 (see: docker compose -f hyperion/docker-compose.yml ps)" >&2
  exit 1
fi

echo "Services:"
echo "  Elasticsearch  http://127.0.0.1:9200"
echo "  MongoDB        mongodb://127.0.0.1:27017"
echo "  Redis          redis://127.0.0.1:6399"
echo "  RabbitMQ       amqp://127.0.0.1:5672  (UI http://127.0.0.1:15672 guest/guest)"
echo ""
echo "Next: bash scripts/setup-hyperion.sh"
