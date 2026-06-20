#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/env.sh"

ECOSYSTEM="${ROOT}/ecosystem.json"

echo "=== SikaChain Ecosystem ==="
python3 - <<'PY' "${ECOSYSTEM}"
import json, sys
e = json.load(open(sys.argv[1]))
print(f"Chain: {e['chain']['name']}  id={e['chain']['chainId'][:16]}…")
print()
for k, p in e["projects"].items():
    print(f"  {k:20} {p['role']}")
PY

echo ""
"${ROOT}/scripts/status.sh" 2>/dev/null || true

echo ""
echo "=== Project paths ==="
python3 - <<'PY' "${ECOSYSTEM}"
import json, os, sys
e = json.load(open(sys.argv[1]))
for k, p in e["projects"].items():
    path = p.get("path", "")
    ok = os.path.isdir(path)
    print(f"  {'✓' if ok else '✗'} {k}: {path}")
PY

echo ""
echo "=== Next steps ==="
echo "  All-in-one: scripts/dev-ready.sh"
echo "  Chain:      scripts/bootstrap-dev.sh  |  scripts/stop-all.sh"
echo "  Upgrade:    scripts/upgrade-contracts.sh (WASM only)"
echo "  App:        ${SCRIPT_DIR}/start-app.sh  →  ${SIKA_APP_URL}"
echo "  Website:    ${SCRIPT_DIR}/start-web.sh  →  ${SIKA_CHAIN_WEB_URL}"
echo "  Verify:     cd \"${SIKA_CHAIN_WEB_DIR}\" && npm run verify:stack"
echo "  Tests:      scripts/run-contract-tests.sh"
echo "  Deploy:     scripts/deploy-sika-system.sh (fresh reset only)"
