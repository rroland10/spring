# Hyperion on SikaChain testnet

Wallet **Activity** and explorer history need Hyperion v2 indexing SHIP from a block producer.

## Prerequisites

| Service | Requirement |
|---------|-------------|
| nodeos | `state_history_plugin`, ports **8888** (RPC) + **8080** (SHIP) reachable from indexer host |
| Docker | Linux amd64 host (or cloud VM) — same as dev Hyperion |

## Local docker testnet (same machine as SikaChainDev)

When nodeos runs in Docker on `:18890` with SHIP on `:18090`:

```bash
bash scripts/setup-hyperion-testnet-local.sh
```

- Reuses dev backing services (ES/Rabbit/Mongo on network `hyperion`)
- Testnet API: `http://127.0.0.1:7002` (dev Hyperion stays on `:7001`)
- Wire app: `APPLY=1 RPC_HOST_PORT=18890 bash scripts/sync-testnet-app-env.sh`

## Quick setup (hosted / VPS)

```bash
# After testnet nodeos is live
export TESTNET_CHAIN_ID=<from-get_info>
export TESTNET_RPC_URL=https://rpc.testnet.sikachain.gh
export TESTNET_SHIP_URL=ws://bp1.testnet.sikachain.gh:8080   # or Fly internal URL

bash scripts/setup-hyperion-testnet.sh
```

This clones [hyperion-history-api](https://github.com/eosrio/hyperion-history-api) if needed, writes `config/connections.json`, and starts:

```bash
docker compose -f deploy/testnet/docker-compose.hyperion.yml up -d
```

API default: `http://127.0.0.1:7001` — put TLS in front for `https://hyperion.testnet.sikachain.gh`.

## Verify

```bash
HYPERION_URL=http://127.0.0.1:7001 bash scripts/check-hyperion.sh

NODE_URL=https://rpc.testnet.sikachain.gh \
  EXPECT_CHAIN_ID=$TESTNET_CHAIN_ID \
  HYPERION_URL=https://hyperion.testnet.sikachain.gh \
  bash scripts/verify-testnet.sh
```

## Client env

```bash
TESTNET_HYPERION_URL=https://hyperion.testnet.sikachain.gh \
  node scripts/export-testnet-env.mjs
```

## SHIP reachability

| Deploy | RPC | SHIP |
|--------|-----|------|
| Docker nodeos on VPS | public :8888 | public :8080 (firewall indexer IP) |
| Fly.io BP | `https://<app>.fly.dev` | expose :8080 in `fly.toml` or run Hyperion on same private network |
| Split | RPC load balancer | SHIP only on BP1, indexer in same VPC |

If Hyperion runs in Docker on a **different host** than nodeos, use the **public** RPC and SHIP URLs — `configure-hyperion-testnet.mjs` does not rewrite non-localhost hosts.

## Config only (no start)

```bash
HYPERION_START=0 bash scripts/setup-hyperion-testnet.sh
```

## Related

- [hyperion-dev.md](hyperion-dev.md) — local SikaChainDev
- [testnet-bootstrap.md](testnet-bootstrap.md) — Phase 5
- [testnet-fly.md](testnet-fly.md) — nodeos container
