#!/usr/bin/env bash
# Ensure Sika app serves critical wallet routes (restart if stale dev cache 404s group pages).
#
# Playwright live tests reuse :3003; a long-running next dev can miss new App Router segments
# until restarted — /app/business/group/[name] then returns Next.js 404.
#
# Usage:
#   bash scripts/ensure-wallet-app.sh
#   WALLET_APP_AUTO_RESTART=0 bash scripts/ensure-wallet-app.sh   # probe only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

APP_URL="${SIKA_APP_URL:-http://127.0.0.1:3003}"
PORT="${SIKA_APP_PORT:-3003}"
AUTO_RESTART="${WALLET_APP_AUTO_RESTART:-1}"
PROBE_GROUP="${WALLET_APP_PROBE_GROUP:-sikadev}"

app_status() {
  local path="$1"
  curl -sfL -m 20 -o /dev/null -w "%{http_code}" "${APP_URL}${path}" 2>/dev/null || echo "000"
}

echo "=== ensure-wallet-app ==="
echo "  app=${APP_URL}  probe=/app/business/group/${PROBE_GROUP}"

home="$(app_status "/app/home")"
if [[ "${home}" != "200" ]]; then
  echo "error: GET /app/home → HTTP ${home}" >&2
  echo "  start: bash ${SCRIPT_DIR}/start-app.sh" >&2
  exit 1
fi

group="$(app_status "/app/business/group/${PROBE_GROUP}")"
if [[ "${group}" == "200" ]]; then
  echo "  routes ok"
  exit 0
fi

echo "  GET /app/business/group/${PROBE_GROUP} → HTTP ${group} (expected 200)"

if [[ "${AUTO_RESTART}" != "1" ]]; then
  echo "error: restart the wallet app: bash ${SCRIPT_DIR}/start-app.sh" >&2
  exit 1
fi

echo "  restarting Sika app on :${PORT}..."
if lsof -ti ":${PORT}" >/dev/null 2>&1; then
  lsof -ti ":${PORT}" | xargs kill 2>/dev/null || true
  sleep 2
fi

LOG="${ROOT}/logs/wallet-app.log"
mkdir -p "${ROOT}/logs"
PID="$(bash "${SCRIPT_DIR}/daemonize.sh" "${LOG}" bash "${SCRIPT_DIR}/start-app.sh")"
echo "  pid ${PID}  log ${LOG}"

for ((i = 0; i < 90; i++)); do
  group="$(app_status "/app/business/group/${PROBE_GROUP}")"
  home="$(app_status "/app/home")"
  if [[ "${group}" == "200" && "${home}" == "200" ]]; then
    echo "  routes ok after restart"
    exit 0
  fi
  sleep 2
done

echo "error: app still unhealthy (home=${home} group=${group})" >&2
echo "  see ${LOG}" >&2
exit 1
