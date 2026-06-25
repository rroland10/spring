#!/usr/bin/env node
/**
 * Write SikaChainDev Hyperion connection snippet (connections.json entry + .env hints).
 */
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const chain = JSON.parse(readFileSync(join(ROOT, "chain.json"), "utf8"));
const outDir = join(ROOT, "hyperion", "generated");
mkdirSync(outDir, { recursive: true });

const chainId = chain.chainId;
const rpc = chain.url ?? "http://127.0.0.1:8888";
const ship = process.env.SHIP_URL ?? "ws://127.0.0.1:8080";
const hyperionPort = process.env.HYPERION_PORT ?? "7001";

const connection = {
  chain: chainId,
  alias: chain.chainName ?? "SikaChainDev",
  http: rpc,
  ship,
  start_block: 1,
  expire_after_seconds: 3600,
  fetch_block: true,
  fetch_traces: true,
  fetch_deltas: true,
  index_all: true,
};

writeFileSync(
  join(outDir, "connections.sikachaindev.json"),
  JSON.stringify([connection], null, 2),
  "utf8",
);

const envHints = `# Hyperion local (generated)
HYPERION_PORT=${hyperionPort}
ELASTIC_HOST=http://127.0.0.1:9200
MONGO_URI=mongodb://127.0.0.1:27017
REDIS_HOST=127.0.0.1
REDIS_PORT=6399
RABBITMQ_HOST=127.0.0.1
RABBITMQ_PORT=5672
# SikaChainDev SHIP (ENABLE_SHIP=1 on nodeos)
SHIP_URL=${ship}
`;

writeFileSync(join(outDir, "hyperion.env.hints"), envHints, "utf8");

console.log("Wrote", join(outDir, "connections.sikachaindev.json"));
console.log("Wrote", join(outDir, "hyperion.env.hints"));
console.log("");
console.log("Merge connections.sikachaindev.json into your Hyperion connections.json");
console.log(`Then set chain.json hyperionUrl to http://127.0.0.1:${hyperionPort} and run sync-app-env.mjs`);
