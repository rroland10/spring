#!/usr/bin/env bash
# Generate WharfKit TypeScript bindings for Sika contracts.
#
# Prefers live RPC (deployed ABIs). Falls back to local WASM build artifacts
# when nodeos is offline — required for Ricardian-rich ABIs before deploy.
#
# Usage:
#   bash generate-bindings.sh
#   SIKA_BINDINGS_LOCAL=1 bash generate-bindings.sh   # force local ABIs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
OUT_DIR="${APP_DIR}/src/contracts"
RPC="${NODE_URL}"
CONTRACTS_DIR="${SIKA_CONTRACTS_DIR:-/Users/randallroland/Desktop/Projects/sikachain sys contract/contracts}"
BUILD_ABI="${CONTRACTS_DIR}/build/contracts"

mkdir -p "${OUT_DIR}"

SYSTEM_ABI="${BUILD_ABI}/sika.system/sika.system.abi"
if [[ -f "${SYSTEM_ABI}" ]]; then
  node "${SCRIPT_DIR}/patch-system-abi.mjs" "${SYSTEM_ABI}" 2>/dev/null || true
fi

use_local=0
if [[ "${SIKA_BINDINGS_LOCAL:-0}" == "1" ]]; then
  use_local=1
elif ! curl -sf "${RPC}/v1/chain/get_info" >/dev/null 2>&1; then
  echo "nodeos offline at ${RPC} — using local ABIs from ${BUILD_ABI}"
  use_local=1
fi

account_on_chain() {
  curl -sf "${RPC}/v1/chain/get_account" \
    -d "{\"account_name\":\"$1\"}" \
    | python3 -c "import json,sys; json.load(sys.stdin); sys.exit(0)" 2>/dev/null
}

generate_one() {
  local account="$1"
  local wasm_name="$2"
  local out_file="${OUT_DIR}/${account}.ts"

  if [[ "${use_local}" == "1" ]]; then
    local abi="${BUILD_ABI}/${wasm_name}/${wasm_name}.abi"
    if [[ ! -f "${abi}" ]]; then
      echo "  skip ${account} — missing ${abi} (run build-sika-contracts-docker.sh)"
      return 0
    fi
    echo "  ${account} ← ${abi}"
    (cd "${APP_DIR}" && npx --yes @wharfkit/cli generate "${account}" -j "${abi}" -f "${out_file}")
    return 0
  fi

  if ! account_on_chain "${account}"; then
    local abi="${BUILD_ABI}/${wasm_name}/${wasm_name}.abi"
    if [[ -f "${abi}" ]]; then
      echo "  ${account} ← ${abi} (local fallback)"
      (cd "${APP_DIR}" && npx --yes @wharfkit/cli generate "${account}" -j "${abi}" -f "${out_file}")
      return 0
    fi
    echo "  skip ${account} (not on chain)"
    return 0
  fi
  echo "  ${account} ← ${RPC}"
  (cd "${APP_DIR}" && npx --yes @wharfkit/cli generate -u "${RPC}" "${account}" -f "${out_file}")
}

echo "Generating bindings → ${OUT_DIR}"

# sika.system WASM is deployed on the privileged system account (sika in Phase 3)
generate_one "${SIKA_SYSTEM_ACCOUNT}" "sika.system"
generate_one "sika.token" "sika.token"
generate_one "sika.rep" "sika.rep"
generate_one "sika.guard" "sika.guard"
generate_one "sika.rules" "sika.rules"
generate_one "sika.issue" "sika.issue"
generate_one "sika.treas" "sika.treas"

# Standard multisig WASM (upstream eosio.msig source) deployed as sika.msig on SikaChainDev.
MSIG_ACCOUNT="${MSIG_ACCOUNT:-sika.msig}"
MSIG_ABI_SRC="${ROOT}/../unittests/contracts/eosio.msig/eosio.msig.abi"
MSIG_BUILD_ABI="${ROOT}/.msig-build/${MSIG_ACCOUNT}/${MSIG_ACCOUNT}.abi"

if [[ "${use_local}" == "1" ]]; then
  abi="${MSIG_BUILD_ABI}"
  if [[ ! -f "${abi}" ]]; then
    abi="${MSIG_ABI_SRC}"
  fi
  if [[ -f "${abi}" ]]; then
    echo "  ${MSIG_ACCOUNT} ← ${abi}"
    (cd "${APP_DIR}" && npx --yes @wharfkit/cli generate "${MSIG_ACCOUNT}" -j "${abi}" -f "${OUT_DIR}/${MSIG_ACCOUNT}.ts")
  else
    echo "  skip ${MSIG_ACCOUNT} (run deploy-msig.sh)"
  fi
elif account_on_chain "${MSIG_ACCOUNT}"; then
  generate_one "${MSIG_ACCOUNT}" "eosio.msig"
else
  abi="${MSIG_BUILD_ABI}"
  if [[ ! -f "${abi}" ]]; then
    abi="${MSIG_ABI_SRC}"
  fi
  if [[ -f "${abi}" ]]; then
    echo "  ${MSIG_ACCOUNT} ← ${abi} (local fallback)"
    (cd "${APP_DIR}" && npx --yes @wharfkit/cli generate "${MSIG_ACCOUNT}" -j "${abi}" -f "${OUT_DIR}/${MSIG_ACCOUNT}.ts")
  else
    echo "  skip ${MSIG_ACCOUNT} (run deploy-msig.sh)"
  fi
fi

AA_ACCOUNT="${ATOMICASSETS_ACCOUNT:-atomicassets}"
AA_ABI="${ROOT}/.atomicassets-build/${AA_ACCOUNT}/${AA_ACCOUNT}.abi"
if [[ ! -f "${AA_ABI}" ]]; then
  AA_ABI="${ROOT}/.atomicassets-build/atomicassets.abi"
fi
if [[ -f "${AA_ABI}" ]]; then
  echo "  ${AA_ACCOUNT} ← ${AA_ABI}"
  (cd "${APP_DIR}" && npx --yes @wharfkit/cli generate "${AA_ACCOUNT}" -j "${AA_ABI}" -f "${OUT_DIR}/${AA_ACCOUNT}.ts")
elif account_on_chain "${AA_ACCOUNT}"; then
  generate_one "${AA_ACCOUNT}" "atomicassets"
fi

# Legacy imports still reference contracts/eosio.ts — keep ABI in sync on Phase 3 dev.
if [[ "${SIKA_SYSTEM_ACCOUNT}" == "sika" && -f "${OUT_DIR}/sika.ts" ]]; then
  cp "${OUT_DIR}/sika.ts" "${OUT_DIR}/eosio.ts"
  echo "  synced eosio.ts ← sika.ts (legacy alias)"
fi

echo "Done."
