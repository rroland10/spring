#!/usr/bin/env bash
# One-shot Phase 3 bootstrap: SIKACHAIN=ON Spring + protocol `sikaio` + system `sika`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"

export SIKACHAIN_DEV=1
export SIKA_PROTOCOL_ACCOUNT=sikaio
export SIKA_SYSTEM_ACCOUNT=sika

echo "=== SikaChainDev Phase 3 bootstrap ==="
echo "Protocol account: sikaio | System contract: sika (requires Spring -DSIKACHAIN=ON)"
echo ""

if [[ ! -x "${ROOT}/../build/programs/nodeos/nodeos" ]]; then
  echo "error: Spring nodeos not found — run scripts/build-sikachain-spring.sh first"
  exit 1
fi

if [[ "${1:-}" == "--reset" ]]; then
  echo "Building contracts with SIKACHAIN=1..."
  FORCE_CONTRACT_REBUILD=1 SIKACHAIN=1 bash "${SCRIPT_DIR}/build-sika-contracts-docker.sh"
fi

if [[ "${1:-}" == "--reset" ]] || [[ "${SIKA_RESET_CONFIRM:-}" == "yes" ]]; then
  SIKA_RESET_CONFIRM=yes bash "${SCRIPT_DIR}/reset-chain.sh" -y
fi

bash "${SCRIPT_DIR}/bootstrap-dev.sh"

bash "${SCRIPT_DIR}/sync-dev-env.sh"
cp "${APP_DIR}/.env.sikachaindev.phase3" "${APP_DIR}/.env.local"
echo "Synced ${APP_DIR}/.env.local (Phase 3)"

bash "${SCRIPT_DIR}/verify-phase3.sh"

echo ""
echo "=== Phase 3 ready ==="
echo "  Ecosystem: bash scripts/launch-ecosystem.sh --verify"
echo "  Smoke:     bash scripts/smoke-phase3.sh"
echo "  App:       bash scripts/start-app.sh  →  http://127.0.0.1:3003"
echo "  Full verify: SIKACHAIN_DEV=1 VERIFY_ATOMICASSETS=1 bash scripts/verify-dev.sh"
