#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${1:-}" != "-y" ]] && [[ "${SIKA_RESET_CONFIRM:-}" != "yes" ]]; then
  read -r -p "Delete SikaChainDev chain data and wallet? [y/N] " confirm
  if [[ "${confirm}" != [yY] ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

bash "$(dirname "$0")/stop-all.sh" 2>/dev/null || true
rm -rf "${ROOT}/data" "${ROOT}/wallet"
echo "SikaChainDev data cleared. Run start-all.sh to start fresh."
