#!/usr/bin/env bash
# Start Hyperion indexer + API in Docker (required on macOS — node-abieos is Linux-only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HYPERION_DIR="${ROOT}/hyperion"
COMPOSE_DEPS="${HYPERION_DIR}/docker-compose.yml"
COMPOSE_APP="${HYPERION_DIR}/docker-compose.hyperion.yml"

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker not found"
  exit 1
fi

# shellcheck source=lib/docker-ready.sh
source "${SCRIPT_DIR}/lib/docker-ready.sh"
docker_ready || exit 1

echo "=== Hyperion (Docker) for SikaChainDev ==="
if command -v pm2 >/dev/null 2>&1; then
  pm2 delete sikachaindev-indexer sikachaindev-api 2>/dev/null || true
fi

bash "${SCRIPT_DIR}/start-hyperion-deps.sh"

if ! curl -sf http://127.0.0.1:8888/v1/chain/get_info >/dev/null 2>&1; then
  echo "error: nodeos not reachable — run: ENABLE_SHIP=1 bash scripts/restart-ship.sh"
  exit 1
fi
if ! bash "${SCRIPT_DIR}/check-ship.sh" 2>/dev/null; then
  echo "error: SHIP not listening — run: bash scripts/restart-ship.sh"
  exit 1
fi

node "${SCRIPT_DIR}/configure-hyperion-dev.mjs" --docker

echo ""
echo "Building and starting Hyperion containers (first run may take several minutes)..."
docker_compose_up -f "${COMPOSE_DEPS}" -f "${COMPOSE_APP}" --build hyperion-indexer hyperion-api

echo ""
echo "Waiting for Hyperion API on :7001..."
for _ in $(seq 1 60); do
  if curl -sf http://127.0.0.1:7001/v2/health >/dev/null 2>&1; then
    echo "  ok  http://127.0.0.1:7001/v2/health"
    break
  fi
  sleep 5
done

if curl -sf http://127.0.0.1:7001/v2/health >/dev/null 2>&1; then
  python3 -c "
import json
from pathlib import Path
p = Path('${ROOT}/chain.json')
c = json.loads(p.read_text())
if c.get('hyperionUrl') != 'http://127.0.0.1:7001':
    c['hyperionUrl'] = 'http://127.0.0.1:7001'
    p.write_text(json.dumps(c, indent=2) + chr(10))
    print('Updated chain.json hyperionUrl')
"
  node "${SCRIPT_DIR}/sync-app-env.mjs" --local 2>/dev/null || true
  bash "${SCRIPT_DIR}/check-hyperion.sh" || true
else
  echo "note: API not ready yet — indexer may still be catching up"
  echo "  docker compose -f hyperion/docker-compose.yml -f hyperion/docker-compose.hyperion.yml logs -f hyperion-api"
fi
