#!/usr/bin/env node
/**
 * Write anchor-chain.json for Anchor wallet "Add Blockchain" import.
 *
 * Usage:
 *   node export-anchor-chain.mjs [output-path]
 *   node export-anchor-chain.mjs --testnet-example [output-path]
 */
import { readFileSync, writeFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const args = process.argv.slice(2);
const testnetExample = args[0] === "--testnet-example";
const outArg = testnetExample ? args[1] : args[0];
const out =
  outArg ??
  (testnetExample
    ? join(ROOT, "anchor-chain.testnet.example.json")
    : join(ROOT, "anchor-chain.json"));

const chain = JSON.parse(readFileSync(join(ROOT, "chain.json"), "utf8"));

const testnetChainId = process.env.TESTNET_CHAIN_ID ?? process.env.EXPECT_CHAIN_ID ?? "REPLACE_WITH_CHAIN_ID";
const testnetRpc =
  process.env.TESTNET_RPC_URL ?? process.env.NODE_URL ?? "https://rpc.testnet.sikachain.gh";
const testnetHyperion = process.env.TESTNET_HYPERION_URL ?? process.env.HYPERION_URL;

const anchor = testnetExample
  ? {
      name: process.env.TESTNET_CHAIN_NAME ?? "SikaChain Testnet",
      chainId: testnetChainId,
      nodeUrl: testnetRpc,
      ...(testnetHyperion ? { hyperionUrl: testnetHyperion.replace(/\/$/, "") } : {}),
      symbol: "SIKA",
      keyPrefix: "PUB_K1",
      testnet: true,
      systemContract: "sika",
      tokenContract: "sika.token",
      tokenSymbol: "SIKA",
      stablecoinSymbol: "CGHS",
      producer: "sika",
      logo: "https://sikachain.com/images/sikachain.svg",
      appName: "Sika",
      notes:
        "Testnet Anchor import. Privileged system account is sika (not eosio). Replace chainId and nodeUrl before publishing.",
    }
  : {
      name: chain.chainName ?? "SikaChain",
      chainId: chain.chainId,
      nodeUrl: chain.url,
      symbol: chain.symbol ?? "SIKA",
      keyPrefix: chain.keyFormat ?? "PUB_K1",
      testnet: true,
      systemContract: chain.systemContract ?? "sika",
      tokenContract: chain.tokenContract ?? "sika.token",
      tokenSymbol: chain.symbol ?? "SIKA",
      stablecoinSymbol: "CGHS",
      producer: chain.producer ?? chain.systemContract ?? "sika",
      logo: "https://sikachain.com/images/sikachain.svg",
      appName: chain.wharfkit?.appName ?? "Sika",
      notes:
        "Import in Anchor: Settings → Blockchains → Add. Privileged system account is sika (not eosio).",
    };

writeFileSync(out, JSON.stringify(anchor, null, 2) + "\n", "utf8");
console.log("Wrote", out);
