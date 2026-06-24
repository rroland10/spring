#!/usr/bin/env bash
# Launch the full dev ecosystem detached from the current shell (survives terminal close).
#
# Usage:
#   bash scripts/launch-ecosystem.sh              # quick start (chain + apps)
#   bash scripts/launch-ecosystem.sh --verify     # quick start + verify-all
#   bash scripts/launch-ecosystem.sh --full       # full dev-ready bootstrap
#   bash scripts/stop-ecosystem.sh                # stop
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${ROOT}/data"
mkdir -p "${DATA_DIR}"

export SIKACHAIN_DEV="${SIKACHAIN_DEV:-1}"
export SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT:-sika}"
export ENABLE_SHIP="${ENABLE_SHIP:-1}"

LOG="${DATA_DIR}/ecosystem-launcher.log"
PID_FILE="${DATA_DIR}/ecosystem.pid"

if [[ -f "${PID_FILE}" ]]; then
  OLD_PID="$(cat "${PID_FILE}")"
  if kill -0 "${OLD_PID}" 2>/dev/null; then
    echo "Ecosystem launcher already running (pid ${OLD_PID}, log ${LOG})"
    exit 0
  fi
  rm -f "${PID_FILE}"
fi

ARGS=()
QUICK=1
VERIFY=0
for arg in "$@"; do
  case "${arg}" in
    --full) QUICK=0 ;;
    --quick) QUICK=1 ;;
    --verify) VERIFY=1 ;;
  esac
done
[[ "${QUICK}" -eq 1 ]] && ARGS+=(--quick)
[[ "${VERIFY}" -eq 1 ]] && ARGS+=(--verify)
if [[ ${#ARGS[@]} -eq 0 ]]; then
  ARGS=(--quick)
fi

LAUNCHER_PID="$(bash "${SCRIPT_DIR}/daemonize.sh" "${LOG}" \
  env SIKACHAIN_DEV="${SIKACHAIN_DEV}" \
  SIKA_SYSTEM_ACCOUNT="${SIKA_SYSTEM_ACCOUNT}" \
  ENABLE_SHIP="${ENABLE_SHIP}" \
  bash "${SCRIPT_DIR}/start-ecosystem.sh" "${ARGS[@]}")"
echo "${LAUNCHER_PID}" > "${PID_FILE}"

echo "Ecosystem launching in background (pid ${LAUNCHER_PID})"
echo "  log: ${LOG}"
echo "  tail -f ${LOG}"
echo "  health: bash scripts/check-health.sh"
echo "  quick:  bash scripts/quick-verify.sh"
echo "  verify: bash scripts/verify-stack.sh  |  bash scripts/verify-predeploy.sh"
echo "  stop: bash scripts/stop-ecosystem.sh"
