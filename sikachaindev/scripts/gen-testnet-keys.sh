#!/usr/bin/env bash
# Generate fresh testnet genesis + block producer keys (DO NOT COMMIT output).
#
# Usage:
#   bash scripts/gen-testnet-keys.sh
#   BP_COUNT=21 bash scripts/gen-testnet-keys.sh
#
# Writes to config/testnet/generated/ (gitignored):
#   genesis.json, producers-<N>.json, README.txt
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/env.sh"

OUT="${ROOT}/config/testnet/generated"
BP_COUNT="${BP_COUNT:-6}"
TEMPLATE="${ROOT}/config/testnet/genesis.example.json"
STAMP="$(date -u +"%Y-%m-%dT%H:%M:%S.000")"

mkdir -p "${OUT}"

if ! command -v "${CLEOS}" >/dev/null 2>&1 && [[ ! -x "${CLEOS}" ]]; then
  echo "error: cleos not found — build Spring first"
  exit 1
fi

gen_keypair() {
  local label="$1"
  local tmp
  tmp="$(mktemp)"
  "${CLEOS}" create key --to-console > "${tmp}" 2>&1
  local pub pvt
  pub="$(grep -E '^Public key:' "${tmp}" | awk '{print $3}')"
  pvt="$(grep -E '^Private key:' "${tmp}" | awk '{print $3}')"
  rm -f "${tmp}"
  if [[ -z "${pub}" || -z "${pvt}" ]]; then
    echo "error: cleos create key failed for ${label}" >&2
    exit 1
  fi
  echo "${pub}"$'\t'"${pvt}"
}

echo "=== gen-testnet-keys (BP_COUNT=${BP_COUNT}) ==="
echo "  output: ${OUT}"
echo ""

read -r GENESIS_PUB GENESIS_PVT < <(gen_keypair genesis)
echo "  genesis public: ${GENESIS_PUB}"

python3 - <<PY "${TEMPLATE}" "${OUT}/genesis.json" "${GENESIS_PUB}" "${STAMP}"
import json, sys
template, out, pub, ts = sys.argv[1:5]
g = json.load(open(template))
g["initial_key"] = pub.replace("PUB_K1_", "EOS") if pub.startswith("PUB_K1_") else pub
g["initial_timestamp"] = ts
json.dump(g, open(out, "w"), indent=2)
open(out, "a").write("\n")
PY

# cleos/Spring genesis uses EOS prefix; normalize PUB_K1 → EOS for initial_key
GENESIS_EOS="$(python3 -c "import json; print(json.load(open('${OUT}/genesis.json'))['initial_key'])")"

producers_json="${OUT}/producers-${BP_COUNT}.json"
python3 - <<'PY' "${producers_json}" "${BP_COUNT}"
import json, sys
out, n = sys.argv[1], int(sys.argv[2])
data = {"description": f"Testnet block producers ({n}) — DO NOT COMMIT", "producers": []}
json.dump(data, open(out, "w"), indent=2)
open(out, "a").write("\n")
PY

idx=0
while [[ "${idx}" -lt "${BP_COUNT}" ]]; do
  idx=$((idx + 1))
  name="$(printf 'sikabp%c' "$(python3 -c "print(chr(96+${idx}))")")"
  read -r pub pvt < <(gen_keypair "${name}")
  pub_eos="${pub}"
  if [[ "${pub}" == PUB_K1_* ]]; then
    pub_eos="EOS${pub#PUB_K1_}"
  fi
  echo "  ${name}: ${pub_eos}"
  python3 - <<PY "${producers_json}" "${name}" "${pub_eos}" "${pvt}"
import json, sys
path, name, pub, pvt = sys.argv[1:5]
d = json.load(open(path))
d["producers"].append({"name": name, "pub": pub, "pvt": pvt})
json.dump(d, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
done

cat > "${OUT}/README.txt" <<EOF
SikaChain testnet key material — KEEP OFFLINE / DO NOT COMMIT

Generated: ${STAMP}
Genesis initial_key: ${GENESIS_EOS}
Genesis private: ${GENESIS_PVT}

Files:
  genesis.json       — mount into nodeos container
  producers-${BP_COUNT}.json — use with bootstrap-testnet.sh

Bootstrap:
  PRODUCERS_JSON=${OUT}/producers-${BP_COUNT}.json \\
  NODE_URL=https://rpc.testnet.sikachain.gh \\
  bash scripts/bootstrap-testnet.sh

Import genesis key to keosd before bootstrap:
  cleos wallet import --private-key ${GENESIS_PVT}
EOF

chmod 600 "${OUT}/README.txt" "${OUT}/producers-${BP_COUNT}.json" 2>/dev/null || true

echo ""
echo "Wrote ${OUT}/genesis.json"
echo "Wrote ${producers_json}"
echo "Wrote ${OUT}/README.txt"
echo ""
echo "Next:"
echo "  1. Mount ${OUT}/genesis.json in deploy/testnet/docker-compose.yml"
echo "  2. Import genesis key: cleos wallet import --private-key <see README.txt>"
echo "  3. Start nodeos, then: PRODUCERS_JSON=${producers_json} bash scripts/bootstrap-testnet.sh"
