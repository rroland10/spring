#!/usr/bin/env node
/**
 * Production settlement worker (§9.6) — BullMQ + Redis.
 *
 * Requires REDIS_URL. Falls back message points to settlement-worker.mjs for dev cron.
 *
 * Usage:
 *   REDIS_URL=redis://127.0.0.1:6379 node settlement-bullmq-worker.mjs
 *   SETTLEMENT_CRON='0 */6 * * *' REDIS_URL=... node settlement-bullmq-worker.mjs
 */
import { runFullSettlementCycle } from "./settlement-lib.mjs";

const REDIS_URL = process.env.REDIS_URL;
const QUEUE_NAME = process.env.SETTLEMENT_QUEUE ?? "sika-settlement";
const CRON = process.env.SETTLEMENT_CRON ?? "0 */6 * * *";
const RUN_ONCE = process.env.SETTLEMENT_ONCE === "1";

if (!REDIS_URL) {
  console.error(
    "[settlement-bullmq] REDIS_URL required. Dev fallback: settlement-worker.mjs"
  );
  process.exit(1);
}

let Queue;
let Worker;
try {
  ({ Queue, Worker } = await import("bullmq"));
} catch {
  console.error(
    "[settlement-bullmq] bullmq not installed — run: npm install in sikachaindev/scripts"
  );
  process.exit(1);
}

const connection = { url: REDIS_URL };

async function runJob() {
  const out = await runFullSettlementCycle();
  console.log(JSON.stringify({ at: new Date().toISOString(), ...out }));
  return out;
}

if (RUN_ONCE) {
  await runJob();
  process.exit(0);
}

const queue = new Queue(QUEUE_NAME, { connection });

await queue.add(
  "settlement-cycle",
  {},
  {
    repeat: { pattern: CRON },
    removeOnComplete: 50,
    removeOnFail: 20,
  }
);

const worker = new Worker(
  QUEUE_NAME,
  async () => runJob(),
  { connection, concurrency: 1 }
);

worker.on("failed", (job, err) => {
  console.error(`[settlement-bullmq] job ${job?.id} failed:`, err.message);
});

console.log(
  `[settlement-bullmq] queue=${QUEUE_NAME} cron="${CRON}" redis=${REDIS_URL}`
);

process.on("SIGINT", async () => {
  await worker.close();
  await queue.close();
  process.exit(0);
});
