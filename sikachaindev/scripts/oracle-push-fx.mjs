#!/usr/bin/env node
/**
 * Push licensed-rail FX quotes on-chain via sika.treas::pushfx (sika.oracle auth).
 *
 * Usage:
 *   node oracle-push-fx.mjs
 *   FX_SYMBOLS=CGHS,CNGN node oracle-push-fx.mjs
 */
import { FX_SYMBOLS, pushFxRates } from "./settlement-lib.mjs";

const symbols = (process.env.FX_SYMBOLS ?? "CGHS")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const results = await pushFxRates(symbols.length ? symbols : Object.keys(FX_SYMBOLS));
console.log(JSON.stringify(results, null, 2));
