/**
 * Shared settlement helpers (used by worker + Next.js API route).
 */
import { spawnSync } from "node:child_process";
import { createHmac } from "node:crypto";
import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { signFxAttestation } from "./oracle-crypto.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
export const ROOT = join(__dirname, "..");
export const NODE_URL = process.env.NODE_URL ?? "http://127.0.0.1:8888";
export const WALLET_URL = process.env.WALLET_URL ?? "http://127.0.0.1:8899";
export const SYSTEM = process.env.SIKA_SYSTEM_ACCOUNT ?? "sika";
export const ORACLE = process.env.SIKA_ORACLE_ACCOUNT ?? "sika.oracle";
export const FX_TTL_SECONDS = Number(process.env.FX_TTL_SECONDS ?? 86400);
export const ORACLE_ATTEST_SECRET = process.env.ORACLE_ATTEST_SECRET ?? "";
export const ORACLE_SIGN_KEY = process.env.ORACLE_SIGN_KEY ?? "";
export const ORACLE_REQUIRE_SIGNED =
  process.env.ORACLE_REQUIRE_SIGNED_PUSH === "1" ||
  process.env.ORACLE_REQUIRE_SIGNED === "1";

const BUILD_BIN = join(ROOT, "..", "build", "programs", "cleos", "cleos");
export const CLEOS = process.env.CLEOS ?? (existsSync(BUILD_BIN) ? BUILD_BIN : "cleos");

/** Local stable symbol → fiat code for open.er-api (CUSD ≈ USD). */
export const FX_SYMBOLS = {
  CGHS: "GHS",
  CNGN: "NGN",
  CKES: "KES",
};

export function cleosArgs() {
  return ["--url", NODE_URL, "--wallet-url", WALLET_URL];
}

export function unlockWallet() {
  spawnSync(CLEOS, [...cleosArgs(), "wallet", "open"], { stdio: "ignore" });
  const pwPath = join(ROOT, "wallet", ".password");
  if (existsSync(pwPath)) {
    const pw = readFileSync(pwPath, "utf8").trim();
    spawnSync(CLEOS, [...cleosArgs(), "wallet", "unlock", "--password", pw], {
      stdio: "ignore",
    });
  }
}

export function pushAction(contract, action, data, auth) {
  const r = spawnSync(
    CLEOS,
    [
      ...cleosArgs(),
      "push",
      "action",
      contract,
      action,
      JSON.stringify(data),
      "-p",
      auth,
    ],
    { encoding: "utf8" }
  );
  if (r.status !== 0) {
    throw new Error(`${contract}::${action} failed: ${r.stderr || r.stdout}`);
  }
  return r.stdout;
}

export function parseMarkets(raw) {
  if (!raw?.trim()) {
    return [{ market: "gh", quantity: "1000.0000 CGHS" }];
  }
  return raw.split(",").map((entry) => {
    const [market, quantity] = entry.split(":");
    if (!market || !quantity) {
      throw new Error(`invalid SETTLEMENT_MARKETS entry: ${entry}`);
    }
    return { market: market.trim(), quantity: quantity.trim() };
  });
}

/** Fetch USD→fiat and return CUSD ppm for local stable (4 decimals). */
export async function fetchCusdPpm(fiatCode) {
  const res = await fetch(`https://open.er-api.com/v6/latest/USD`);
  if (!res.ok) {
    throw new Error(`FX API HTTP ${res.status}`);
  }
  const data = await res.json();
  const perUsd = data?.rates?.[fiatCode];
  if (!perUsd || !Number.isFinite(perUsd) || perUsd <= 0) {
    throw new Error(`missing rate for ${fiatCode}`);
  }
  // 1 local unit = (1 / perUsd) USD ≈ CUSD; ppm = local→cusd ratio × 1e6
  const ppm = Math.round((1_000_000 / perUsd));
  return { ppm, perUsd, source: "open.er-api" };
}

/** Dev attestation (off-chain until pushfxsig lands on-chain). */
export function signFxQuote({ symbol, ppm, ttlSeconds, ts = Date.now() }) {
  if (!ORACLE_ATTEST_SECRET) {
    return { attested: false, reason: "ORACLE_ATTEST_SECRET unset" };
  }
  const payload = `${symbol}:${ppm}:${ttlSeconds}:${ts}`;
  const sig = createHmac("sha256", ORACLE_ATTEST_SECRET).update(payload).digest("hex");
  return { attested: true, payload, sig, ts };
}

export async function pushFxRates(symbols = Object.keys(FX_SYMBOLS)) {
  unlockWallet();
  const results = [];
  const useSigned = Boolean(ORACLE_SIGN_KEY);
  const publishedAtUs = BigInt(Date.now()) * 1000n;

  for (const sym of symbols) {
    const fiat = FX_SYMBOLS[sym];
    if (!fiat) continue;
    const { ppm, perUsd, source } = await fetchCusdPpm(fiat);
    const attestation = signFxQuote({
      symbol: sym,
      ppm,
      ttlSeconds: FX_TTL_SECONDS,
    });

    if (useSigned) {
      const { signature, publishedAtUs: pubUs } = signFxAttestation({
        privateKey: ORACLE_SIGN_KEY,
        symbol: sym,
        ppm,
        ttlSeconds: FX_TTL_SECONDS,
        publishedAtUs,
      });
      pushAction(
        "sika.treas",
        "pushfxsig",
        [`4,${sym}`, ppm, FX_TTL_SECONDS, Number(pubUs), signature],
        `${ORACLE}@active`
      );
      results.push({
        symbol: sym,
        fiat,
        ppm,
        perUsd,
        source,
        attestation,
        mode: "pushfxsig",
        publishedAtUs: String(pubUs),
      });
    } else {
      pushAction(
        "sika.treas",
        "pushfx",
        [`4,${sym}`, ppm, FX_TTL_SECONDS],
        `${ORACLE}@active`
      );
      results.push({ symbol: sym, fiat, ppm, perUsd, source, attestation, mode: "pushfx" });
    }
  }
  return results;
}

export async function runSettlementCycle(markets) {
  unlockWallet();
  const results = [];
  for (const { market, quantity } of markets) {
    pushAction("sika.treas", "accruefee", [market, quantity], `${SYSTEM}@active`);
    pushAction("sika.treas", "sweep", [market], `${SYSTEM}@active`);
    results.push({ market, quantity, status: "ok" });
  }
  return results;
}

export async function runFullSettlementCycle(options = {}) {
  const markets = parseMarkets(
    options.markets ?? process.env.SETTLEMENT_MARKETS
  );
  const pushFx = options.pushFx ?? process.env.SETTLEMENT_PUSH_FX !== "0";
  const fx = pushFx ? await pushFxRates() : [];
  const settlement = await runSettlementCycle(markets);
  return { fx, settlement };
}
