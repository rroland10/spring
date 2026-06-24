#!/usr/bin/env bash
# Exit 0 when nodeos SHIP endpoint is listening (state_history_plugin).
set -euo pipefail

PORT="${SHIP_PORT:-8080}"
if lsof -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "OK: SHIP listening on 127.0.0.1:${PORT}"
  exit 0
fi

echo "FAIL: SHIP not listening on 127.0.0.1:${PORT}" >&2
echo "Start with: bash scripts/restart-ship.sh" >&2
exit 1
