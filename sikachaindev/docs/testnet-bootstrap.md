# SikaChain testnet bootstrap runbook

Step-by-step guide to stand up a **new** public testnet (not a copy of SikaChainDev). For architecture overview see [testnet-deploy.md](testnet-deploy.md).

**Do not reuse** dev genesis keys, chain ID, or `producers-6.json` private keys on a public network.

## Phase 0 — Artifacts

| Item | Source |
|------|--------|
| nodeos / cleos / keosd | [rroland10/spring](https://github.com/rroland10/spring) tag **`sikachain-dev-sika-v4`** |
| System contracts | `sikachain sys contract` — `SIKACHAIN=1 ./build.sh` |
| eosio.boot | `bash scripts/build-system-contracts.sh` or Spring `unittests/contracts/eosio.boot/` |

```bash
git clone https://github.com/rroland10/spring.git
cd spring && git checkout sikachain-dev-sika-v4
bash sikachaindev/scripts/build-sikachain-spring.sh
```

## Phase 1 — Keys and genesis

**Automated (recommended):**

```bash
bash scripts/gen-testnet-keys.sh
# or: BP_COUNT=21 bash scripts/gen-testnet-keys.sh
```

Writes gitignored `config/testnet/generated/` — `genesis.json`, `producers-<N>.json`, `README.txt` (genesis private key). **Never commit** that directory.

**Manual alternative:**

```bash
cleos create key --to-console
# Copy config/testnet/genesis.example.json → set initial_key + initial_timestamp
```

Mount genesis at run time (compose example):

```bash
# deploy/testnet/docker-compose.yml — uncomment:
# - ../../config/testnet/generated/genesis.json:/etc/sikachain/genesis.json:ro
```

Start **one** nodeos with empty data dir (or use Docker — [testnet-fly.md](testnet-fly.md)):

```bash
nodeos --genesis-json /var/lib/sikachain/genesis.json \
  --data-dir /var/lib/sikachain/data \
  --config-dir /var/lib/sikachain/config
```

Record **chain ID** (needed for wallet + Anchor):

```bash
curl -s https://rpc.testnet.sikachain.gh/v1/chain/get_info | jq -r .chain_id
```

Spring with `SIKACHAIN=ON` creates privileged account **`sika`** at genesis (not `eosio`).

## Phase 1b — Local Docker dry-run (optional)

One-shot bootstrap on a fresh docker volume (uses port **18890** by default so dev `:8888` stays free):

```bash
bash scripts/gen-testnet-keys.sh
RESET=1 RPC_HOST_PORT=18890 bash scripts/bootstrap-docker-testnet.sh
```

This script:

1. Starts GHCR `sikachain-dev-sika-v4` nodeos as genesis `sika`
2. Runs `bootstrap-testnet.sh` (contracts + 6 BPs registered, **no votes**)
3. Keeps producing as **`sika`** — votes would activate a multi-BP Savanna schedule and stall a single container

For schedule activation + rotation: `SKIP_BP_VOTE=0 SKIP_SCHEDULE=0` and multinode (`start-6bp-cluster.sh`).

**Wire Sika app to local docker testnet:**

```bash
APPLY=1 RPC_HOST_PORT=18890 bash scripts/sync-testnet-app-env.sh
TESTNET_LOCAL=1 RPC_HOST_PORT=18890 bash scripts/start-app.sh
SKIP_BP_VOTE=1 NODE_URL=http://127.0.0.1:18890 WALLET_UI=1 bash scripts/test-features.sh
```

**Full local predeploy gate:**

```bash
bash scripts/verify-testnet-stack.sh          # all checks + client export
# QUICK=1 skips cleos matrix (~2 min faster)
```

**Local Hyperion (activity / history on docker testnet):**

```bash
bash scripts/setup-hyperion-testnet-local.sh   # API :7002, SHIP from :18090
APPLY=1 RPC_HOST_PORT=18890 bash scripts/sync-testnet-app-env.sh
TESTNET_LOCAL=1 bash scripts/start-app.sh
```

Verify:

```bash
NODE_URL=http://127.0.0.1:18890 EXPECT_CHAIN_ID=<from-get_info> bash scripts/verify-testnet.sh
```

**Docker notes:** v4 image bakes `enable-stale-production`, `wasm-runtime=eos-vm`, unlimited `max-transaction-time`, and higher genesis CPU limits (`genesis.example.json`) so `sika.system` WASM deploy succeeds under amd64 emulation.

## Phase 2 — Producer config

**Container / Fly:** see [testnet-fly.md](testnet-fly.md) (`deploy/testnet/Dockerfile.nodeos`, `fly.toml.example`).

1. Copy `config/testnet/nodeos-producer.example.ini` → each BP `config.ini` (bare metal).
2. Set `producer-name`, `signature-provider`, P2P public endpoints, peer list.
3. Enable `state_history_plugin` on at least one node (SHIP for Hyperion).
4. Terminate TLS with `config/testnet/nginx-rpc.example.conf` (or Caddy/Fly/ALB).

CORS: set `access-control-allow-origin` to your wallet origin (`https://app.sikachain.gh`) or use a same-origin API proxy.

## Phase 3 — Contract bootstrap

From an ops machine with the genesis **`sika`** key in keosd:

```bash
export NODE_URL=https://rpc.testnet.sikachain.gh   # or http://127.0.0.1:8888 on BP1
export WALLET_URL=http://127.0.0.1:8899

# Import genesis sika private key into wallet first!

bash scripts/bootstrap-testnet.sh
```

This runs the same path as dev:

1. `deploy-sika-system.sh` — token → system → eosio.boot → init → satellites → treas → msig
2. `bootstrap-6bp.sh` or `BP_COUNT=21` — register/vote producers
3. `verify-testnet.sh` — RPC smoke

**Generate new BP keys** for testnet; do not publish `config/producers-6.json` dev keys. Use output from `gen-testnet-keys.sh`:

```bash
PRODUCERS_JSON=config/testnet/generated/producers-6.json bash scripts/bootstrap-testnet.sh
```

Local dry-run against SikaChainDev (same scripts, dev chain id):

```bash
ALLOW_DEV_CHAIN=1 bash scripts/bootstrap-testnet.sh
```

## Phase 4 — Multinode (optional)

After contracts + votes on a single node:

1. Graceful stop; copy `data/` to each BP host (or snapshot).
2. `ENABLE_SHIP=1 bash scripts/start-6bp-cluster.sh` pattern — see [cleos-dev.md](cleos-dev.md#multinode-6-bp-cluster).
3. On cloud: replicate `start-bp-cluster.sh` logic per host (one data clone per BP, mesh P2P).

## Phase 5 — Hyperion

See **[testnet-hyperion.md](testnet-hyperion.md)** for full steps.

```bash
TESTNET_CHAIN_ID=... \
  TESTNET_RPC_URL=https://rpc.testnet.sikachain.gh \
  TESTNET_SHIP_URL=ws://bp1.testnet.sikachain.gh:8080 \
  bash scripts/setup-hyperion-testnet.sh
```

## Phase 6 — Client publish

```bash
TESTNET_CHAIN_ID=<from-get_info> \
  TESTNET_RPC_URL=https://rpc.testnet.sikachain.gh \
  TESTNET_HYPERION_URL=https://hyperion.testnet.sikachain.gh \
  TESTNET_APP_URL=https://app.sikachain.gh \
  node scripts/export-testnet-env.mjs /tmp/sika-app-production.env

TESTNET_CHAIN_ID=<id> \
  TESTNET_RPC_URL=https://rpc.testnet.sikachain.gh \
  TESTNET_HYPERION_URL=https://hyperion.testnet.sikachain.gh \
  node scripts/export-anchor-chain.mjs --testnet-example
```

Paste env into Vercel/Fly. Publish Anchor JSON for users (Settings → Blockchains → Add).

## Phase 7 — Gates

Remote:

```bash
NODE_URL=https://rpc.testnet.sikachain.gh \
  EXPECT_CHAIN_ID=<chain-id> \
  HYPERION_URL=https://hyperion.testnet.sikachain.gh \
  bash scripts/verify-testnet.sh
```

Wallet smoke: [gh-v1-launch.md](gh-v1-launch.md) section 5 (PWA, Anchor, cGHS send, Activity, MSIG).

## Checklist

- [ ] New genesis key; chain ID recorded
- [ ] `sika` privileged; no `eosio` account
- [ ] SIKA + CGHS created on `sika.token`
- [ ] `sika.msig` privileged
- [ ] ≥6 producers registered and voted
- [ ] HTTPS RPC + Hyperion live
- [ ] `verify-testnet.sh` pass
- [ ] Wallet env deployed (`gh-v1`, no `DEV_WALLET`)
- [ ] Anchor chain JSON published

## Related

- [testnet-deploy.md](testnet-deploy.md) — component map
- [gh-v1-launch.md](gh-v1-launch.md) — wallet rollout
- `config/testnet/` — genesis, nodeos, nginx templates
