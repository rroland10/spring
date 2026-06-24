#!/usr/bin/env node
/**
 * Seed §6.4 per-market payout prefs on sika.treas.
 *
 * Usage:
 *   node seed-marketprefs.mjs
 *   MARKET_PREFS='gh:CGHS:0:1:1,ng:CNGN:0:0:0' node seed-marketprefs.mjs
 *
 * Format per entry: market:SYMBOL:allow_cusd:allow_ggold:compliance_ready
 */
import { SYSTEM, pushAction, unlockWallet } from "./settlement-lib.mjs";

const DEFAULT_PREFS =
  process.env.MARKET_PREFS ??
  "gh:CGHS:0:1:1,ng:CNGN:0:0:0,tz:CGHS:0:0:0";

function parsePrefs(raw) {
  return raw.split(",").map((entry) => {
    const [market, symbol, allowCusd, allowGgold, ready] = entry.split(":");
    if (!market || !symbol) {
      throw new Error(`invalid MARKET_PREFS entry: ${entry}`);
    }
    return {
      market,
      localSymbol: `4,${symbol}`,
      allowCusd: allowCusd === "1",
      allowGgold: allowGgold === "1",
      complianceReady: ready === "1",
    };
  });
}

unlockWallet();
const results = [];

for (const pref of parsePrefs(DEFAULT_PREFS)) {
  pushAction(
    "sika.treas",
    "setmarketpref",
    [
      SYSTEM,
      pref.market,
      pref.localSymbol,
      pref.allowCusd,
      pref.allowGgold,
      pref.complianceReady,
    ],
    `${SYSTEM}@active`
  );
  results.push(pref);
}

console.log(JSON.stringify({ seeded: results.length, prefs: results }, null, 2));
