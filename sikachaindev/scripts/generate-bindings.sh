#!/usr/bin/env bash
# Generate WharfKit TypeScript bindings from deployed SikaChainDev contracts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

APP_DIR="${SIKA_APP_DIR:-/Users/randallroland/Desktop/Projects/Sika app}"
OUT_DIR="${APP_DIR}/src/contracts"
RPC="${NODE_URL}"

mkdir -p "${OUT_DIR}"

if ! curl -sf "${RPC}/v1/chain/get_info" >/dev/null 2>&1; then
  echo "error: nodeos not running at ${RPC} — run bootstrap-dev.sh first"
  exit 1
fi

echo "Generating bindings → ${OUT_DIR}"
echo "RPC: ${RPC}"

for account in sika.token "${SIKA_SYSTEM_ACCOUNT}" sika.rep sika.guard sika.rules sika.issue; do
  if ! "${CLEOS}" --url "${RPC}" get account "${account}" >/dev/null 2>&1; then
    echo "  skip ${account} (not on chain)"
    continue
  fi
  file="${OUT_DIR}/${account}.ts"
  echo "  ${account} → ${file}"
  npx --yes @wharfkit/cli generate -u "${RPC}" "${account}" -f "${file}"
done

echo "Done."
