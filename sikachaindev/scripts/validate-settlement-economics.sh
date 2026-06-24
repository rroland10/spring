#!/usr/bin/env bash
# Run §10 settlement economics scenarios and print governance checks.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCENARIOS=(gh_pilot gh_scale gh_ng_launch multi_market)

echo "=== Settlement economics validation (§10) ==="

for scenario in "${SCENARIOS[@]}"; do
  echo ""
  echo "--- MODEL_SCENARIO=${scenario} ---"
  MODEL_SCENARIO="${scenario}" node "${SCRIPT_DIR}/model-settlement-economics.mjs" | node -e "
    const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
    for (const c of d.checks ?? []) {
      console.log((c.ok ? 'OK' : 'FAIL') + ': ' + c.id + ' — ' + c.detail);
    }
    if (d.tier1?.coverageRatioDaily != null) {
      console.log('Coverage: ' + d.tier1.coverageRatioDaily.toFixed(2) + '× daily Tier-1');
    }
    if (d.governanceSignOff) {
      console.log('Sign-off ready: ' + d.governanceSignOff.ready);
    }
  "
done

echo ""
echo "=== Custom volumes (optional) ==="
echo "MODEL_GH_DAILY_CGHS=250000 MODEL_BPS=21 node model-settlement-economics.mjs"

if [[ -n "${MODEL_GH_DAILY_CGHS:-}" || -n "${MODEL_NG_DAILY_CNGN:-}" ]]; then
  echo ""
  echo "--- Env custom volumes ---"
  node "${SCRIPT_DIR}/model-settlement-economics.mjs" | node -e "
    const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
    console.log(JSON.stringify({ scenario: d.scenario, tier1: d.tier1, governanceSignOff: d.governanceSignOff }, null, 2));
  "
fi

echo ""
echo "=== validate-settlement-economics complete ==="
