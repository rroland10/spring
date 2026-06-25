#!/usr/bin/env bash
# Stop Hyperion indexer + API containers (Docker).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DEPS="${ROOT}/hyperion/docker-compose.yml"
COMPOSE_APP="${ROOT}/hyperion/docker-compose.hyperion.yml"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker not found"
  exit 1
fi

docker compose -f "${COMPOSE_DEPS}" -f "${COMPOSE_APP}" stop hyperion-indexer hyperion-api 2>/dev/null || true
docker compose -f "${COMPOSE_DEPS}" -f "${COMPOSE_APP}" rm -f hyperion-indexer hyperion-api 2>/dev/null || true
echo "Hyperion containers stopped"
