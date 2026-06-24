#!/usr/bin/env bash
# Run smoke-wallet.sh for every dev account in chain.json (with privateKey).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ACCOUNTS=()
while IFS= read -r name; do
  [[ -n "${name}" ]] && ACCOUNTS+=("${name}")
done < <(python3 -c "
import json
c = json.load(open('${ROOT}/chain.json'))
skip = {'eosio', 'sika', c.get('systemContract', 'sika')}
for name in sorted(c.get('accounts', {})):
    if c['accounts'][name].get('privateKey') and name not in skip:
        print(name)
")

if [[ ${#ACCOUNTS[@]} -eq 0 ]]; then
  echo "No dev accounts in chain.json"
  exit 1
fi

FAIL=0
for acct in "${ACCOUNTS[@]}"; do
  echo ""
  if bash "${SCRIPT_DIR}/smoke-wallet.sh" "${acct}"; then
    :
  else
    FAIL=1
  fi
done

echo ""
if [[ "${FAIL}" -eq 0 ]]; then
  echo "=== smoke-dev-accounts complete — all ${#ACCOUNTS[@]} accounts passed ==="
else
  echo "=== smoke-dev-accounts failed ===" >&2
  exit 1
fi
