#!/usr/bin/env node
/**
 * §10 illustrative economics model — NOT financial advice.
 *
 * Estimates Tier-1 reserve runway, sweep/yield split, and break-even fee volume
 * from dev-default on-chain parameters and assumed daily local-fee accrual.
 *
 * Usage:
 *   node model-settlement-economics.mjs
 *   MODEL_SCENARIO=gh_ng_launch node model-settlement-economics.mjs
 *   MODEL_GH_DAILY_CGHS=250000 MODEL_BPS=21 node model-settlement-economics.mjs
 */
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const BUILD_BIN = join(ROOT, "..", "build", "programs", "cleos", "cleos");
const CLEOS = process.env.CLEOS ?? (existsSync(BUILD_BIN) ? BUILD_BIN : "cleos");
const NODE_URL = process.env.NODE_URL ?? "http://127.0.0.1:8888";

const SCENARIOS = {
  gh_pilot: { gh: 50_000, ng: 0, tz: 0, label: "Ghana pilot (50k CGHS/day fees)" },
  gh_scale: { gh: 500_000, ng: 0, tz: 0, label: "Ghana scale (500k CGHS/day)" },
  gh_ng_launch: {
    gh: 200_000,
    ng: 150_000,
    tz: 0,
    label: "Ghana + Nigeria launch",
  },
  multi_market: {
    gh: 300_000,
    ng: 200_000,
    tz: 100_000,
    label: "Gh + Ng + Tz",
  },
};

function envNum(key, fallback) {
  const raw = process.env[key];
  if (raw == null || raw === "") return fallback;
  const n = Number(raw);
  return Number.isFinite(n) ? n : fallback;
}

function parseCusd(amount) {
  return parseFloat(String(amount ?? "0").split(/\s+/)[0] ?? "0") || 0;
}

function cleosJson(args) {
  const r = spawnSync(CLEOS, ["--url", NODE_URL, ...args], { encoding: "utf8" });
  if (r.status !== 0) return null;
  try {
    return JSON.parse(r.stdout);
  } catch {
    return null;
  }
}

function loadOnChainParams() {
  const params = cleosJson(["get", "table", "sika.treas", "sika.treas", "params"]);
  const reserve = cleosJson(["get", "table", "sika.treas", "sika.treas", "reserve"]);
  const p = params?.rows?.[0] ?? {};
  const r = reserve?.rows?.[0] ?? {};
  return {
    sweep_slice_bps: Number(p.sweep_slice_bps ?? 2500),
    fee_to_yield_bps: Number(p.fee_to_yield_bps ?? 2500),
    max_subsidy_per_market_bps: Number(p.max_subsidy_per_market_bps ?? 500),
    cost_recovery_cusd: parseCusd(p.cost_recovery_cusd) || 250,
    reserve_cusd: parseCusd(r.cusd_balance),
    reserve_ggold_bps: Number(r.reserve_gold_bps ?? 3000),
  };
}

function dailyMarketFlow(localFeesCusdRef, params) {
  const swept = (localFeesCusdRef * params.sweep_slice_bps) / 10_000;
  const toYield = (swept * params.fee_to_yield_bps) / 10_000;
  const toReserve = swept - toYield;
  return { localFeesCusdRef, swept, toYield, toReserve };
}

function resolveScenario() {
  const name = process.env.MODEL_SCENARIO ?? "gh_pilot";
  if (SCENARIOS[name]) return { name, ...SCENARIOS[name] };

  return {
    name: "custom",
    label: "Custom env volumes",
    gh: envNum("MODEL_GH_DAILY_CGHS", 50_000),
    ng: envNum("MODEL_NG_DAILY_CNGN", 0),
    tz: envNum("MODEL_TZ_DAILY_CGHS", 0),
  };
}

const params = loadOnChainParams();
const scenario = resolveScenario();
const bps = envNum("MODEL_BPS", 21);
const pegPpm = envNum("MODEL_CUSD_PPM", 1_000_000);

const markets = ["gh", "ng", "tz"].map((id) => {
  const localWhole = Number(scenario[id] ?? 0);
  const cusdRef = (localWhole * pegPpm) / 1_000_000;
  return {
    market: id,
    dailyLocalFees: localWhole,
    dailyCusdRef: cusdRef,
    ...dailyMarketFlow(cusdRef, params),
  };
});

const totals = markets.reduce(
  (acc, m) => ({
    dailyLocalFees: acc.dailyLocalFees + m.dailyLocalFees,
    dailyCusdRef: acc.dailyCusdRef + m.dailyCusdRef,
    swept: acc.swept + m.swept,
    toYield: acc.toYield + m.toYield,
    toReserve: acc.toReserve + m.toReserve,
  }),
  { dailyLocalFees: 0, dailyCusdRef: 0, swept: 0, toYield: 0, toReserve: 0 }
);

const tier1DailyCost = params.cost_recovery_cusd * bps;
const tier1MonthlyCost = tier1DailyCost * 30;
/** Days reserve covers Tier-1 BP costs if fee income stops entirely. */
const reserveRunwayDays =
  tier1DailyCost > 0
    ? Math.floor(params.reserve_cusd / tier1DailyCost)
    : null;
/** Days until reserve doubles at current net inflow (inflow minus Tier-1 burn). */
const reserveNetDaily = totals.toReserve - tier1DailyCost;
const reserveGrowthDays =
  reserveNetDaily > 0
    ? Math.ceil(params.reserve_cusd / reserveNetDaily)
    : reserveNetDaily < 0
      ? Math.floor(params.reserve_cusd / Math.abs(reserveNetDaily))
      : null;

const breakEvenDailyCusd =
  params.sweep_slice_bps > 0
    ? tier1DailyCost / (params.sweep_slice_bps / 10_000) /
      (1 - params.fee_to_yield_bps / 10_000)
    : null;

const coverageRatio =
  tier1DailyCost > 0 ? totals.toReserve / tier1DailyCost : null;

const report = {
  disclaimer:
    "Illustrative model only — not financial advice. Peg 1 local = 1 CUSD unless MODEL_CUSD_PPM set.",
  scenario: { id: scenario.name, label: scenario.label },
  onChain: params,
  assumptions: {
    bps,
    pegPpm,
    daysPerMonth: 30,
  },
  markets,
  totals,
  tier1: {
    dailyCostCusd: tier1DailyCost,
    monthlyCostCusd: tier1MonthlyCost,
    reserveCoverageDaysAtZeroFees: reserveRunwayDays,
    dailyReserveInflowCusd: totals.toReserve,
    dailyReserveNetCusd: reserveNetDaily,
    reserveGrowthOrDepletionDays: reserveGrowthDays,
    coverageRatioDaily: coverageRatio,
    breakEvenDailyFeeVolumeCusdRef: breakEvenDailyCusd,
  },
  rexYield: {
    dailyYieldPoolCusdRef: totals.toYield,
    annualizedYieldPoolCusdRef: totals.toYield * 365,
    note: "REX APY depends on total REX stake — not computed here.",
  },
  checks: [
    {
      id: "tier1_self_funding",
      ok: coverageRatio != null && coverageRatio >= 1,
      detail:
        coverageRatio != null
          ? `Reserve inflow / Tier-1 cost = ${coverageRatio.toFixed(2)}× daily`
          : "No Tier-1 cost",
    },
    {
      id: "bootstrap_runway",
      ok:
        reserveRunwayDays == null ||
        reserveRunwayDays >= 90 ||
        (coverageRatio != null && coverageRatio >= 1 && reserveNetDaily > 0),
      detail:
        reserveRunwayDays == null
          ? "No Tier-1 cost baseline"
          : reserveNetDaily > 0 && coverageRatio != null && coverageRatio >= 1
            ? `Reserve growing (+${reserveNetDaily.toFixed(0)} CUSD/day net); ${reserveRunwayDays} days static runway if fees stop`
            : `~${reserveRunwayDays} days Tier-1 coverage from current reserve if fees stop`,
    },
  ],
};

report.governanceSignOff = {
  ready: report.checks.every((c) => c.ok),
  failedChecks: report.checks.filter((c) => !c.ok).map((c) => c.id),
};

console.log(JSON.stringify(report, null, 2));
process.exit(0);
