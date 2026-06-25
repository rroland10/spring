#!/usr/bin/env node
/**
 * Ensure sika.system ABI exports native tables needed for wallet RPC queries.
 * Merges missing types/tables from Spring eosio.system.abi (delband, etc.).
 *
 * Usage:
 *   node patch-system-abi.mjs [path/to/sika.system.abi]
 */
import { readFileSync, writeFileSync } from "fs";
import { dirname, join, resolve } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const EOSIO_ABI = join(ROOT, "..", "unittests/contracts/eosio.system/eosio.system.abi");
const DEFAULT_ABI = join(
  process.env.SIKA_CONTRACTS_DIR ?? "/Users/randallroland/Desktop/Projects/sikachain sys contract/contracts",
  "build/contracts/sika.system/sika.system.abi",
);

const abiPath = resolve(process.argv[2] ?? DEFAULT_ABI);
const eosio = JSON.parse(readFileSync(EOSIO_ABI, "utf8"));
const target = JSON.parse(readFileSync(abiPath, "utf8"));

const NEED_STRUCTS = ["delegated_bandwidth"];
const NEED_TABLES = ["delband"];

function mergeByName(arr, items, label) {
  const names = new Set(arr.map((x) => x.name));
  let added = 0;
  for (const item of items) {
    if (!names.has(item.name)) {
      arr.push(item);
      names.add(item.name);
      added++;
      console.log(`  + ${label} ${item.name}`);
    }
  }
  return added;
}

console.log(`Patching ${abiPath}`);
const structsAdded = mergeByName(
  target.structs,
  eosio.structs.filter((t) => NEED_STRUCTS.includes(t.name)),
  "struct",
);
const tablesAdded = mergeByName(
  target.tables,
  eosio.tables.filter((t) => NEED_TABLES.includes(t.name)),
  "table",
);

if (structsAdded + tablesAdded === 0) {
  console.log("  (already complete)");
} else {
  writeFileSync(abiPath, JSON.stringify(target, null, 4) + "\n", "utf8");
  console.log(`Wrote ${abiPath}`);
}
