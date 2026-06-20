#!/usr/bin/env bash
# Publish latest Sika contract WASM to a running SikaChainDev node (no genesis bootstrap).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export SIKA_UPGRADE_ONLY=1
exec bash "${SCRIPT_DIR}/deploy-sika-system.sh"
