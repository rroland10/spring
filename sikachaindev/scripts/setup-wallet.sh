#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/env.sh"
BUILD_BIN="${ROOT}/../build/programs"
if [[ -z "${CLEOS:-}" ]]; then
  if [[ -x "${BUILD_BIN}/cleos/cleos" ]]; then
    CLEOS="${BUILD_BIN}/cleos/cleos"
  else
    CLEOS="cleos"
  fi
fi
WALLET_URL="${WALLET_URL:-http://127.0.0.1:8899}"
NODE_URL="${NODE_URL:-http://127.0.0.1:8888}"
DEV_PRIVATE_KEY="5KQwrPbwdL6PhXujxW37FSSQZ1JiwsST4cqQzDeyXtP79zkvFD3"
PASSWORD_FILE="${ROOT}/wallet/.password"

if ! command -v "${CLEOS}" >/dev/null 2>&1; then
  echo "error: cleos not found. Install Spring or set CLEOS=/path/to/cleos"
  exit 1
fi

CLEOS_ARGS=(--url "${NODE_URL}" --wallet-url "${WALLET_URL}")

if ! curl -sf "${WALLET_URL}/v1/wallet/list_wallets" >/dev/null 2>&1; then
  echo "error: keosd not reachable at ${WALLET_URL} — run start-keosd.sh first"
  exit 1
fi

mkdir -p "${ROOT}/wallet"

echo "Creating default wallet and importing SikaChainDev dev key..."
if [[ ! -f "${ROOT}/wallet/default.wallet" ]]; then
  "${CLEOS}" "${CLEOS_ARGS[@]}" wallet create --file "${PASSWORD_FILE}"
else
  "${CLEOS}" "${CLEOS_ARGS[@]}" wallet open || true
fi

WALLET_PASSWORD="$(tr -d '\n' < "${PASSWORD_FILE}")"
"${CLEOS}" "${CLEOS_ARGS[@]}" wallet unlock --password "${WALLET_PASSWORD}" 2>/dev/null || true
if ! "${CLEOS}" "${CLEOS_ARGS[@]}" wallet keys | grep -Eq "EOS6MRyAjQq8ud7hVNYcfnVPJqcVpscN5So8BhtHuGYqET5GDW5CV|PUB_K1_6MRyAjQq8ud7hVNYcfnVPJqcVpscN5So8BhtHuGYqET5BoDq63"; then
  "${CLEOS}" "${CLEOS_ARGS[@]}" wallet import --private-key "${DEV_PRIVATE_KEY}"
fi

export ROOT NODE_URL WALLET_URL
export CLEOS_BIN="${CLEOS}"

python3 <<'PY'
import json, os, subprocess

root = os.environ["ROOT"]
cleos = os.environ["CLEOS_BIN"]
node_url = os.environ["NODE_URL"]
wallet_url = os.environ["WALLET_URL"]
c = json.load(open(os.path.join(root, "chain.json")))
skip = {"eosio", "sika", c.get("systemContract", "sika")}

keys_out = subprocess.run(
    [cleos, "--url", node_url, "--wallet-url", wallet_url, "wallet", "keys"],
    capture_output=True,
    text=True,
).stdout

for name, acct in sorted(c.get("accounts", {}).items()):
    pvt = acct.get("privateKey")
    pub = acct.get("publicKey", "")
    legacy = acct.get("publicKeyLegacy", "")
    if not pvt or name in skip:
        continue
    markers = [m for m in (pub, legacy, pub.replace("PUB_K1_", "")) if m]
    if any(m in keys_out for m in markers):
        continue
    print(f"Importing {name} dev key...")
    subprocess.run(
        [
            cleos,
            "--url",
            node_url,
            "--wallet-url",
            wallet_url,
            "wallet",
            "import",
            "--private-key",
            pvt,
        ],
        check=True,
    )
PY

PRODUCERS_6="${ROOT}/config/producers-6.json"
if [[ -f "${PRODUCERS_6}" ]]; then
  python3 <<'PY'
import json, os, subprocess

root = os.environ["ROOT"]
cleos = os.environ["CLEOS_BIN"]
node_url = os.environ["NODE_URL"]
wallet_url = os.environ["WALLET_URL"]
path = os.path.join(root, "config", "producers-6.json")
keys_out = subprocess.run(
    [cleos, "--url", node_url, "--wallet-url", wallet_url, "wallet", "keys"],
    capture_output=True,
    text=True,
).stdout
for p in json.load(open(path)).get("producers", []):
    pvt = p.get("pvt")
    pub = p.get("pub", "")
    name = p.get("name", "")
    if not pvt:
        continue
    if pub and pub in keys_out:
        continue
    print(f"Importing {name} producer key...")
    subprocess.run(
        [
            cleos,
            "--url",
            node_url,
            "--wallet-url",
            wallet_url,
            "wallet",
            "import",
            "--private-key",
            pvt,
        ],
        check=False,
    )
PY
fi

echo ""
echo "Wallet ready. Example:"
echo "  cleos --url ${NODE_URL} --wallet-url ${WALLET_URL} create account ${SIKA_SYSTEM_ACCOUNT} myaccount PUB_K1_..."
