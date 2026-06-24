#!/usr/bin/env node
/**
 * Dev settlement worker (§9.6 stand-in for BullMQ).
 */
import { runFullSettlementCycle } from "./settlement-lib.mjs";

const INTERVAL = Number(process.env.SETTLEMENT_INTERVAL_MS ?? 3_600_000);
const ONCE = process.env.SETTLEMENT_ONCE === "1";

if (ONCE) {
  const out = await runFullSettlementCycle();
  console.log(JSON.stringify(out, null, 2));
  process.exit(0);
}

console.log(`[settlement-worker] every ${INTERVAL}ms`);
const first = await runFullSettlementCycle();
console.log(JSON.stringify(first, null, 2));
setInterval(() => {
  runFullSettlementCycle()
    .then((out) => console.log(JSON.stringify(out)))
    .catch((err) => console.error("[settlement-worker]", err.message));
}, INTERVAL);
