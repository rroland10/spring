#!/usr/bin/env bash
# Write runtime nodeos config for 6-BP lite mode: produce as the first voted BP
# (sikabpa) with stale production. Keeps the genesis `sika` key as a secondary
# signature provider so blocks can still advance during schedule handoff.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

PRODUCERS_JSON="${PRODUCERS_JSON:-${ROOT}/config/producers-6.json}"
CHAIN_JSON="${ROOT}/chain.json"
RUNTIME_CONFIG="${ROOT}/data/runtime-config"
KEY_FORMAT_MJS="${SCRIPT_DIR}/lib/key-format.mjs"

read -r name pub pvt < <(python3 - <<'PY' "${PRODUCERS_JSON}"
import json, sys
p = json.load(open(sys.argv[1]))["producers"][0]
print(p["name"], p["pub"], p["pvt"])
PY
)

pub_k1="$(node "${KEY_FORMAT_MJS}" to-pub-k1 "${pub}")"
sika_pub="$(python3 -c "import json; print(json.load(open('${CHAIN_JSON}'))['publicKey'])")"
sika_pvt="$(python3 -c "import json; print(json.load(open('${CHAIN_JSON}'))['privateKey'])")"

mkdir -p "${RUNTIME_CONFIG}"
{
  sed -e "s/^producer-name = .*/producer-name = ${name}/" \
      -e "s|^signature-provider = .*|signature-provider = ${pub_k1}=KEY:${pvt}|" \
      "${ROOT}/config/config.ini"
  echo "signature-provider = ${sika_pub}=KEY:${sika_pvt}"
} > "${RUNTIME_CONFIG}/config.ini"
echo "lite producer config: ${name} (+ genesis ${SIKA_SYSTEM_ACCOUNT} fallback key)"
