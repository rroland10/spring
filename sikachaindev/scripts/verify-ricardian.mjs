#!/usr/bin/env node
/**
 * Verify Sika actions have Ricardian contracts in built ABIs.
 *
 * Usage:
 *   node verify-ricardian.mjs
 */
import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const CONTRACTS =
  process.env.SIKA_CONTRACTS_DIR ??
  "/Users/randallroland/Desktop/Projects/sikachain sys contract/contracts";

const MSIG_ABI_CANDIDATES = [
  join(ROOT, ".msig-build/sika.msig/sika.msig.abi"),
  join(ROOT, ".msig-build/eosio.msig/eosio.msig.abi"),
  join(ROOT, "..", "unittests/contracts/eosio.msig/eosio.msig.abi"),
];

const REQUIRED = {
  "sika.system": [
    "buyrex",
    "sellrex",
    "refund",
    "claimrewards",
    "claimrexyld",
    "voteproducer",
    "delegatebw",
    "undelegatebw",
    "deposit",
    "buyrambytes",
    "buyram",
    "sellram",
    "regproxy",
    "updateauth",
    "linkauth",
    "unlinkauth",
    "deleteauth",
    "regproducer",
    "regproducer2",
    "claimprod",
    "claimvest",
    "withdraw",
    "unregprod",
    "attestcompl",
    "canceldelay",
    "newaccount",
    "setcode",
    "setabi",
  ],
  "sika.treas": [
    "setpayoutpref",
    "clearyield",
    "sweep",
    "accruefee",
    "paycost",
    "subsidize",
    "rebalance",
    "setparams",
    "setmarketpref",
    "setfx",
    "pushfx",
    "pushfxsig",
    "setoraclekey",
    "init",
    "creditreserve",
  ],
  "sika.token": ["transfer", "open", "issue", "create", "close", "retire"],
  "sika.msig": ["propose", "approve", "unapprove", "cancel", "exec", "invalidate"],
};

let failed = false;

for (const [contract, actions] of Object.entries(REQUIRED)) {
  let abiPath = join(CONTRACTS, "build", "contracts", contract, `${contract}.abi`);
  if (contract === "sika.msig") {
    abiPath = MSIG_ABI_CANDIDATES.find((p) => existsSync(p)) ?? abiPath;
  }
  if (!existsSync(abiPath)) {
    console.error(`MISSING ABI: ${abiPath}`);
    failed = true;
    continue;
  }
  const abi = JSON.parse(readFileSync(abiPath, "utf8"));
  const byName = Object.fromEntries(
    (abi.actions ?? []).map((a) => [a.name, a.ricardian_contract ?? ""])
  );
  for (const action of actions) {
    const rc = byName[action];
    if (!rc || rc.trim() === "") {
      console.error(`FAIL: ${contract}::${action} — no ricardian_contract`);
      failed = true;
    } else {
      console.log(`OK: ${contract}::${action} (${rc.length} chars)`);
    }
  }
  const empty = (abi.actions ?? []).filter(
    (a) => !a.ricardian_contract?.trim()
  ).length;
  console.log(`  ${contract}: ${empty} actions still without Ricardian`);
}

process.exit(failed ? 1 : 0);
