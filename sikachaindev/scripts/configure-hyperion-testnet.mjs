#!/usr/bin/env node
/**
 * Write Hyperion config for a hosted SikaChain testnet.
 *
 * Usage:
 *   TESTNET_CHAIN_ID=... TESTNET_RPC_URL=https://... TESTNET_SHIP_URL=ws://... \
 *     node configure-hyperion-testnet.mjs [--docker]
 *
 * Requires hyperion-history-api clone at hyperion/hyperion-history-api
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const HYPERION = join(ROOT, "hyperion", "hyperion-history-api");
const CONFIG_DIR = join(HYPERION, "config");
const CHAINS_DIR = join(CONFIG_DIR, "chains");
const CHAIN_SHORT = process.env.HYPERION_CHAIN_SHORT ?? "sikachaintestnet";

const chainId = process.env.TESTNET_CHAIN_ID ?? process.env.EXPECT_CHAIN_ID;
const hostRpc = process.env.TESTNET_RPC_URL ?? process.env.NODE_URL;
const hostShip = process.env.TESTNET_SHIP_URL ?? process.env.SHIP_URL;
const chainName = process.env.TESTNET_CHAIN_NAME ?? "SikaChain Testnet";
const apiPort = process.env.HYPERION_PORT ?? "7001";
const providerUrl = process.env.TESTNET_APP_URL ?? "https://app.sikachain.gh";

if (!chainId || chainId.includes("REPLACE")) {
  console.error("error: set TESTNET_CHAIN_ID");
  process.exit(1);
}
if (!hostRpc) {
  console.error("error: set TESTNET_RPC_URL");
  process.exit(1);
}
if (!hostShip) {
  console.error("error: set TESTNET_SHIP_URL (ws://bp-host:8080)");
  process.exit(1);
}

const refPath = join(HYPERION, "references/config.ref.json");
if (!existsSync(refPath)) {
  console.error(`error: clone Hyperion first — missing ${HYPERION}`);
  console.error('  git clone --depth 1 https://github.com/eosrio/hyperion-history-api "' + HYPERION + '"');
  process.exit(1);
}

const dockerMode =
  process.argv.includes("--docker") || process.env.HYPERION_DOCKER === "1";

mkdirSync(CHAINS_DIR, { recursive: true });

function dockerHost(url) {
  if (!dockerMode) return url;
  try {
    const u = new URL(url);
    if (u.hostname === "127.0.0.1" || u.hostname === "localhost") {
      u.hostname = "host.docker.internal";
      return u.toString().replace(/\/$/, "");
    }
  } catch {
    /* ws:// */
    return url.replace("127.0.0.1", "host.docker.internal");
  }
  return url;
}

const connections = {
  amqp: {
    host: dockerMode ? "rabbitmq:5672" : "127.0.0.1:5672",
    api: dockerMode ? "rabbitmq:15672" : "127.0.0.1:15672",
    protocol: "http",
    user: "guest",
    pass: "guest",
    vhost: "/",
    frameMax: "0x10000",
  },
  elasticsearch: {
    protocol: "http",
    host: dockerMode ? "elasticsearch:9200" : "127.0.0.1:9200",
    ingest_nodes: dockerMode ? ["elasticsearch:9200"] : ["127.0.0.1:9200"],
    user: "",
    pass: "",
  },
  redis: { host: dockerMode ? "redis" : "127.0.0.1", port: dockerMode ? 6379 : 6399 },
  mongodb: {
    enabled: true,
    host: dockerMode ? "mongodb" : "127.0.0.1",
    port: 27017,
    database_prefix: "hyperion",
    user: "",
    pass: "",
  },
  chains: {
    [CHAIN_SHORT]: {
      chain_id: chainId,
      alias: chainName,
      http: dockerHost(hostRpc),
      ship: dockerHost(hostShip),
      start_block: 1,
      expire_after_seconds: 3600,
      fetch_block: true,
      fetch_traces: true,
      fetch_deltas: true,
      index_all: true,
    },
  },
  alerts: {
    triggers: {
      onApiStart: { enabled: false, cooldown: 30, emitOn: ["http"] },
      onIndexerError: { enabled: false, cooldown: 30, emitOn: ["http"] },
    },
    providers: {
      telegram: { enabled: false, botToken: "", destinationIds: [] },
      http: { enabled: false, server: "", path: "", useAuth: false, user: "", pass: "" },
      email: {
        enabled: false,
        sourceEmail: "",
        destinationEmails: [],
        smtp: "",
        port: 465,
        tls: true,
        user: "",
        pass: "",
      },
    },
  },
};

const refConfig = JSON.parse(readFileSync(refPath, "utf8"));
const chainConfig = structuredClone(refConfig);
chainConfig.api.chain_name = chainName;
chainConfig.api.server_addr = "0.0.0.0";
chainConfig.api.server_port = Number(apiPort);
chainConfig.api.server_name = `hyperion.testnet.sikachain.gh`;
chainConfig.api.provider_name = "SikaChain Testnet";
chainConfig.api.provider_url = providerUrl;
chainConfig.api.chain_api = dockerHost(hostRpc);
chainConfig.settings.chain = CHAIN_SHORT;
chainConfig.settings.parser = "3.2";
chainConfig.indexer.live_reader = true;
chainConfig.indexer.abi_scan_mode = false;

writeFileSync(join(CONFIG_DIR, "connections.json"), JSON.stringify(connections, null, 2), "utf8");
const chainConfigPath = join(CHAINS_DIR, `${CHAIN_SHORT}.config.json`);
writeFileSync(chainConfigPath, JSON.stringify(chainConfig, null, 2), "utf8");

const generated = join(ROOT, "hyperion", "generated");
mkdirSync(generated, { recursive: true });
writeFileSync(
  join(generated, "connections.testnet.json"),
  JSON.stringify([connections.chains[CHAIN_SHORT]], null, 2),
  "utf8",
);

console.log("Wrote", join(CONFIG_DIR, "connections.json"));
console.log("Wrote", chainConfigPath);
console.log("Wrote", join(generated, "connections.testnet.json"));
console.log("");
console.log("Start: docker compose -f sikachaindev/deploy/testnet/docker-compose.hyperion.yml up -d");
