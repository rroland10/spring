#!/usr/bin/env node
/**
 * Register sika.oracle attestation public key on sika.treas (setoraclekey).
 *
 * Usage:
 *   ORACLE_SIGN_KEY=PVT_K1_... node setup-oracle-key.mjs
 *   ORACLE_SIGN_KEY=... ORACLE_REQUIRE_SIGNED=1 node setup-oracle-key.mjs
 */
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  CLEOS,
  ORACLE,
  ORACLE_REQUIRE_SIGNED,
  ORACLE_SIGN_KEY,
  SYSTEM,
  cleosArgs,
  pushAction,
  unlockWallet,
} from "./settlement-lib.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

function loadAntelope() {
  const appDir =
    process.env.SIKA_APP_DIR || "/Users/randallroland/Desktop/Projects/Sika app";
  const require = createRequire(import.meta.url);
  const candidates = [
    join(appDir, "node_modules", "@wharfkit", "antelope"),
    join(__dirname, "..", "..", "..", "..", "Sika app", "node_modules", "@wharfkit", "antelope"),
    join(__dirname, "..", "..", "..", "Sika app", "node_modules", "@wharfkit", "antelope"),
  ];
  for (const dir of candidates) {
    try {
      return require(dir);
    } catch {
      /* continue */
    }
  }
  throw new Error("@wharfkit/antelope not found — npm install in Sika app");
}

if (!ORACLE_SIGN_KEY) {
  console.error("ORACLE_SIGN_KEY required (private key for sika.oracle attestation)");
  process.exit(1);
}

const { PrivateKey } = loadAntelope();
const pub = PrivateKey.from(ORACLE_SIGN_KEY).toPublic();

unlockWallet();
pushAction(
  "sika.treas",
  "setoraclekey",
  [SYSTEM, String(pub), ORACLE_REQUIRE_SIGNED],
  `${SYSTEM}@active`
);

console.log(
  JSON.stringify(
    {
      oracle: ORACLE,
      attestKey: String(pub),
      requireSignedPush: ORACLE_REQUIRE_SIGNED,
    },
    null,
    2
  )
);
