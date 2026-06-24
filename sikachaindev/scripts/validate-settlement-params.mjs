#!/usr/bin/env node
/**
 * §10 parameter audit — compare on-chain sika.treas params to dev defaults.
 *
 * Usage: node validate-settlement-params.mjs
 */
import { spawnSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const BUILD_BIN = join(ROOT, "..", "build", "programs", "cleos", "cleos");
const CLEOS = process.env.CLEOS ?? (existsSync(BUILD_BIN) ? BUILD_BIN : "cleos");
const NODE_URL = process.env.NODE_URL ?? "http://127.0.0.1:8888";

const EXPECTED = {
  sweep_slice_bps: 2500,
  max_subsidy_per_market_bps: 500,
  fee_to_yield_bps: 2500,
  reserve_gold_bps: 3000,
  cost_recovery_cusd: 250,
};

function cleosJson(args) {
  const r = spawnSync(CLEOS, ["--url", NODE_URL, ...args], { encoding: "utf8" });
  if (r.status !== 0) {
    throw new Error(r.stderr || r.stdout || "cleos failed");
  }
  return JSON.parse(r.stdout);
}

function parseCusd(amount) {
  return parseFloat(String(amount).split(/\s+/)[0] ?? "0");
}

const paramsRows = cleosJson(["get", "table", "sika.treas", "sika.treas", "params"]).rows;
const reserveRows = cleosJson(["get", "table", "sika.treas", "sika.treas", "reserve"]).rows;
const prefRows = cleosJson(["get", "table", "sika.treas", "sika.treas", "marketpref"]).rows;

const params = paramsRows[0] ?? {};
const reserve = reserveRows[0] ?? {};

const checks = [
  {
    key: "sweep_slice_bps",
    expected: EXPECTED.sweep_slice_bps,
    actual: params.sweep_slice_bps,
  },
  {
    key: "max_subsidy_per_market_bps",
    expected: EXPECTED.max_subsidy_per_market_bps,
    actual: params.max_subsidy_per_market_bps,
  },
  {
    key: "fee_to_yield_bps",
    expected: EXPECTED.fee_to_yield_bps,
    actual: params.fee_to_yield_bps,
  },
  {
    key: "reserve_gold_bps",
    expected: EXPECTED.reserve_gold_bps,
    actual: reserve.reserve_gold_bps,
  },
  {
    key: "cost_recovery_cusd",
    expected: EXPECTED.cost_recovery_cusd,
    actual: parseCusd(params.cost_recovery_cusd),
  },
];

const mismatches = checks.filter((c) => c.actual !== c.expected);
const report = {
  ok: mismatches.length === 0,
  chain: NODE_URL,
  params: {
    sweep_slice_bps: params.sweep_slice_bps,
    fee_to_yield_bps: params.fee_to_yield_bps,
    max_subsidy_per_market_bps: params.max_subsidy_per_market_bps,
    cost_recovery_cusd: params.cost_recovery_cusd,
    initialized: params.initialized,
  },
  reserve: {
    cusd_balance: reserve.cusd_balance,
    ggold_balance: reserve.ggold_balance,
    reserve_gold_bps: reserve.reserve_gold_bps,
  },
  marketPrefs: prefRows.length,
  mismatches: mismatches.map((m) => ({
    param: m.key,
    expected: m.expected,
    actual: m.actual,
  })),
  note: "Illustrative dev defaults only — §10 production sign-off pending volume modelling.",
};

console.log(JSON.stringify(report, null, 2));
process.exit(report.ok ? 0 : 1);
