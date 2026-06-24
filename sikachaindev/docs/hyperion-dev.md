# Hyperion on SikaChainDev (optional)

The Sika app prefers **Hyperion v2** for account history and tx detail. Without Hyperion it falls back to node **v1 history** when the RPC client exposes `get_actions` / `get_transaction` (limited on modern Spring nodes).

## Quick path (no indexer)

Leave `NEXT_PUBLIC_EXPLORER_HYPERION_URL` unset in `.env.sikachaindev`. Transaction lists may be sparse until Hyperion or a history plugin is available.

Sync env from chain config:

```bash
bash scripts/sync-app-env.mjs
```

## Enable SHIP (state history) on nodeos

Hyperion ingests blocks via **SHIP** (`state_history_plugin`). On SikaChainDev, enable it when starting the node:

```bash
ENABLE_SHIP=1 bash scripts/start-node.sh --daemon
# or
ENABLE_SHIP=1 bash scripts/start-all.sh
```

This appends to `data/runtime-config/config.ini`:

- `state_history_plugin`
- `chain-state-history = true`
- `trace-history = true`
- `state-history-endpoint = 127.0.0.1:8080`

SHIP endpoint: `ws://127.0.0.1:8080` (Hyperion connects here).

## Run Hyperion

### Backing services (Docker)

```bash
bash scripts/start-hyperion-deps.sh
bash scripts/setup-hyperion.sh
```

This starts Elasticsearch (:9200), MongoDB (:27017), Redis (:6379), and RabbitMQ (:5672, UI :15672), and writes `hyperion/generated/connections.sikachaindev.json`.

Stop with `bash scripts/stop-hyperion-deps.sh`.

### nodeos SHIP + Hyperion app

Use [eosrio/hyperion-history-api](https://github.com/eosrio/hyperion-history-api) with a `connections.json` entry pointing at:

| Field | SikaChainDev value |
|-------|-------------------|
| chain | `9b2fde923758593c09517f77ed445a3962a9c938f44405dac43b4ccfebbfa57e` |
| http | `http://127.0.0.1:8888` |
| ship | `ws://127.0.0.1:8080` |

Default Hyperion HTTP port is **7001** on macOS (port **7000** is reserved by AirPlay Receiver). After Hyperion is up:

1. Set `"hyperionUrl": "http://127.0.0.1:7001"` in `chain.json`, or
2. Add `NEXT_PUBLIC_EXPLORER_HYPERION_URL=http://127.0.0.1:7001` to the Sika app env

### macOS (Apple Silicon)

Hyperion’s native module `@eosrio/node-abieos` is **Linux x86-64 only**. Use Docker:

```bash
bash scripts/start-hyperion.sh
```

This builds `linux/amd64` containers, binds nodeos RPC/SHIP on `0.0.0.0` when `ENABLE_SHIP=1`, and sets `http-validate-host = false` so Docker can reach RPC via `host.docker.internal`.

Then:

```bash
node scripts/sync-app-env.mjs --local
bash scripts/check-hyperion.sh   # optional smoke test
```

The app proxies browser requests through `/api/hyperion/*` (see `next.config.mjs` rewrites when env is set).

## WharfKit adapter

Optional indexer URL for the relay API:

```bash
# wharfkit adapter/.env
SIKA_INDEXER_URL=http://127.0.0.1:7001
```
