#!/usr/bin/env bash
# Probe SikaChain GTM site explorer (optional unless CHECK_GTM=1).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

GTM_LOCALE="${GTM_LOCALE:-en}"
BASE="${SIKA_CHAIN_WEB_URL}"
EXPLORER="${BASE}/${GTM_LOCALE}/explorer"

FAIL=0

check() {
  local label="$1"
  shift
  if "$@"; then
    echo "  ok  ${label}"
  else
    echo "  FAIL ${label}"
    FAIL=1
  fi
}

echo "=== SikaChain GTM explorer ==="
echo "  url=${EXPLORER}"
echo ""

check "GTM home" curl -sfL -m 15 -o /dev/null "${BASE}/"
check "GTM explorer hub" curl -sfL -m 15 -o /dev/null "${EXPLORER}"
check "GTM account page (sikadev)" curl -sfL -m 15 -o /dev/null "${EXPLORER}/account/sikadev"

if [[ "${FAIL}" -eq 0 ]]; then
  echo ""
  echo "=== GTM explorer ready ==="
  exit 0
fi

echo ""
if [[ "${CHECK_GTM:-0}" == "1" ]]; then
  echo "=== GTM explorer check failed (CHECK_GTM=1) ===" >&2
  exit 1
fi

echo "=== GTM not reachable (optional — start with start-web.sh) ==="
exit 0
