#!/usr/bin/env node
/**
 * Write Hyperion config/connections.json + config/sikachaindev.config.json for local dev.
 */
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const HYPERION = join(ROOT, "hyperion", "hyperion-history-api");
const CONFIG_DIR = join(HYPERION, "config");
const CHAINS_DIR = join(CONFIG_DIR, "chains");
const CHAIN_JSON = JSON.parse(readFileSync(join(ROOT, "chain.json"), "utf8"));
const CHAIN_SHORT = "sikachaindev";

const dockerMode =
  process.argv.includes("--docker") || process.env.HYPERION_DOCKER === "1";

mkdirSync(CHAINS_DIR, { recursive: true });

const hostRpc = CHAIN_JSON.url ?? "http://127.0.0.1:8888";
const hostShip = process.env.SHIP_URL ?? "ws://127.0.0.1:8080";

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
      chain_id: CHAIN_JSON.chainId,
      alias: CHAIN_JSON.chainName ?? "SikaChainDev",
      http: dockerMode
        ? hostRpc.replace("127.0.0.1", "host.docker.internal")
        : hostRpc,
      ship: dockerMode
        ? hostShip.replace("127.0.0.1", "host.docker.internal")
        : hostShip,
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

const refConfig = JSON.parse(
  readFileSync(join(HYPERION, "references/config.ref.json"), "utf8"),
);

const chainConfig = structuredClone(refConfig);
chainConfig.api.chain_name = CHAIN_JSON.chainName ?? "SikaChainDev";
chainConfig.api.server_addr = dockerMode ? "0.0.0.0" : "127.0.0.1";
chainConfig.api.server_port = 7001;
chainConfig.api.server_name = "127.0.0.1:7001";
chainConfig.api.provider_name = "SikaChainDev Local";
chainConfig.api.provider_url = CHAIN_JSON.appUrl ?? "http://127.0.0.1:3003";
chainConfig.api.chain_api = dockerMode
  ? hostRpc.replace("127.0.0.1", "host.docker.internal")
  : hostRpc;
chainConfig.settings.chain = CHAIN_SHORT;
chainConfig.settings.parser = "3.2";
chainConfig.indexer.live_reader = true;
chainConfig.indexer.abi_scan_mode = false;

writeFileSync(
  join(CONFIG_DIR, "connections.json"),
  JSON.stringify(connections, null, 2),
  "utf8",
);
const chainConfigPath = join(CHAINS_DIR, `${CHAIN_SHORT}.config.json`);
writeFileSync(chainConfigPath, JSON.stringify(chainConfig, null, 2), "utf8");

console.log("Wrote", join(CONFIG_DIR, "connections.json"));
console.log("Wrote", chainConfigPath);
console.log("");
if (dockerMode) {
  console.log("Docker mode — start with: bash scripts/start-hyperion.sh");
} else {
  console.log("Native mode requires Linux x86-64 (node-abieos). On macOS use Docker:");
  console.log("  node scripts/configure-hyperion-dev.mjs --docker");
  console.log("  bash scripts/start-hyperion.sh");
}
