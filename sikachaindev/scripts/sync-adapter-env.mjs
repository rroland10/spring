#!/usr/bin/env node
/**
 * Sync wharfkit adapter .env from sikachaindev/chain.json
 *
 *   node sync-adapter-env.mjs
 */
import { readFileSync, writeFileSync, existsSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const ADAPTER_DIR =
  process.env.SIKA_ADAPTER_DIR ??
  "/Users/randallroland/Desktop/Projects/wharfkit adapter";

const chain = JSON.parse(readFileSync(join(ROOT, "chain.json"), "utf8"));
const systemAccount =
  process.env.SIKA_SYSTEM_ACCOUNT ?? chain.systemContract ?? "sika";
const protocolAccount =
  process.env.SIKA_PROTOCOL_ACCOUNT ?? chain.protocolAccount ?? "sikaio";

const envPath = join(ADAPTER_DIR, ".env");
const examplePath = join(ADAPTER_DIR, ".env.example");

const lines = new Map();
if (existsSync(envPath)) {
  for (const line of readFileSync(envPath, "utf8").split("\n")) {
    const m = line.match(/^([A-Z0-9_]+)=/);
    if (m) lines.set(m[1], line);
  }
} else if (existsSync(examplePath)) {
  for (const line of readFileSync(examplePath, "utf8").split("\n")) {
    const m = line.match(/^([A-Z0-9_]+)=/);
    if (m) lines.set(m[1], line);
  }
}

lines.set("PORT", "PORT=4000");
lines.set("SIKA_CHAIN_RPC_URLS", `SIKA_CHAIN_RPC_URLS=${chain.url ?? "http://127.0.0.1:8888"}`);
lines.set("LOG_LEVEL", lines.get("LOG_LEVEL") ?? "LOG_LEVEL=info");
if (chain.hyperionUrl?.trim()) {
  lines.set("SIKA_INDEXER_URL", `SIKA_INDEXER_URL=${chain.hyperionUrl.trim()}`);
}
lines.set("SIKA_TOKEN_CONTRACT", `SIKA_TOKEN_CONTRACT=${chain.tokenContract ?? "sika.token"}`);
lines.set("SIKA_PROTOCOL_ACCOUNT", `SIKA_PROTOCOL_ACCOUNT=${protocolAccount}`);
lines.set("SIKA_SYSTEM_ACCOUNT", `SIKA_SYSTEM_ACCOUNT=${systemAccount}`);
if (!lines.has("DATABASE_URL")) {
  lines.set(
    "DATABASE_URL",
    "DATABASE_URL=postgresql://sika:sika@127.0.0.1:5432/sikachain?connect_timeout=3"
  );
}

const header = `# SikaChainDev — synced from spring/sikachaindev/chain.json (node sync-adapter-env.mjs)\n`;
const body = [
  header.trim(),
  lines.get("PORT"),
  lines.get("SIKA_CHAIN_RPC_URLS"),
  lines.get("LOG_LEVEL"),
  "",
  "# Optional indexer / cache",
  lines.has("REDIS_URL") ? lines.get("REDIS_URL") : "# REDIS_URL=redis://127.0.0.1:6379",
  lines.get("SIKA_INDEXER_URL") ?? "# SIKA_INDEXER_URL=http://127.0.0.1:7001",
  lines.has("DATABASE_URL") ? lines.get("DATABASE_URL") : "# DATABASE_URL=postgresql://...",
  "",
  lines.get("SIKA_TOKEN_CONTRACT"),
  lines.get("SIKA_PROTOCOL_ACCOUNT"),
  lines.get("SIKA_SYSTEM_ACCOUNT"),
  "",
].join("\n");

writeFileSync(envPath, body + "\n", "utf8");
console.log("Wrote", envPath);
