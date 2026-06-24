#!/usr/bin/env bash
# Periodic settlement worker (dev stand-in for BullMQ §9.6).
#
# Reads market fee accruals from the backend / env and pushes on-chain:
#   sika.treas::accruefee  — record local fees + feed accruepoch
#   sika.treas::sweep      — move sweep_slice_bps into reserve + accruepoch
#
# Usage:
#   bash settlement-sweep.sh gh 1000.0000 CGHS
#   MARKETS='gh:1000.0000 CGHS,tz:500.0000 CGHS' bash settlement-sweep.sh
#
# Requires unlocked dev wallet (see deploy-sika-system.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

SIKA_SYSTEM="${SIKA_SYSTEM_ACCOUNT:-sika}"

unlock_wallet() {
  "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet open 2>/dev/null || true
  if [[ -f "${ROOT}/wallet/.password" ]]; then
    local pw
    pw="$(tr -d '\n' < "${ROOT}/wallet/.password")"
    "${CLEOS}" --url "${NODE_URL}" --wallet-url "${WALLET_URL}" wallet unlock --password "${pw}" 2>/dev/null || true
  fi
}

run_market() {
  local market="$1"
  local quantity="$2"
  echo "=== settlement ${market} ${quantity} ==="
  cleos push action sika.treas accruefee "[\"${market}\",\"${quantity}\"]" -p "${SIKA_SYSTEM}@active"
  local n=0
  until cleos push action sika.treas sweep "[\"${market}\"]" -p "${SIKA_SYSTEM}@active"; do
    n=$((n + 1))
    if [[ "${n}" -ge 8 ]]; then
      echo "error: sweep failed after ${n} attempts (market ledger missing?)" >&2
      return 1
    fi
    sleep 0.5
  done
  cleos get table sika.treas sika.treas marketpnl -l "${market}" -u "${market}" 2>/dev/null || true
  cleos get table "${SIKA_SYSTEM}" "${SIKA_SYSTEM}" vestglb 2>/dev/null || true
}

unlock_wallet

if [[ -n "${MARKETS:-}" ]]; then
  IFS=',' read -ra ENTRIES <<< "${MARKETS}"
  for entry in "${ENTRIES[@]}"; do
    market="${entry%%:*}"
    quantity="${entry#*:}"
    run_market "${market}" "${quantity}"
  done
elif [[ $# -ge 2 ]]; then
  run_market "$1" "$2"
else
  echo "usage: $0 <market> <quantity>" >&2
  echo "   or: MARKETS='gh:1000.0000 CGHS,tz:500.0000 CGHS' $0" >&2
  exit 1
fi

echo "=== settlement sweep complete ==="
