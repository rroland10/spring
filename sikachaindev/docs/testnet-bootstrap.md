# SikaChain testnet bootstrap runbook

Step-by-step guide to stand up a **new** public testnet (not a copy of SikaChainDev). For architecture overview see [testnet-deploy.md](testnet-deploy.md).

**Do not reuse** dev genesis keys, chain ID, or `producers-6.json` private keys on a public network.

## Phase 0 — Artifacts

| Item | Source |
|------|--------|
| nodeos / cleos / keosd | [rroland10/spring](https://github.com/rroland10/spring) tag **`sikachain-dev-sika-v2`** |
| System contracts | `sikachain sys contract` — `SIKACHAIN=1 ./build.sh` |
| eosio.boot | `bash scripts/build-system-contracts.sh` or Spring `unittests/contracts/eosio.boot/` |

```bash
git clone https://github.com/rroland10/spring.git
cd spring && git checkout sikachain-dev-sika-v2
bash sikachaindev/scripts/build-sikachain-spring.sh
```

## Phase 1 — Keys and genesis

1. Generate a **new** genesis keypair (store offline):

```bash
cleos create key --to-console
# Note PUB_K1 → initial_key in genesis
```

2. Copy `config/testnet/genesis.example.json` → host path (e.g. `/var/lib/sikachain/genesis.json`).
3. Set `initial_key` to the new public key and `initial_timestamp` to launch UTC.
4. Start **one** nodeos with empty data dir:

```bash
nodeos --genesis-json /var/lib/sikachain/genesis.json \
  --data-dir /var/lib/sikachain/data \
  --config-dir /var/lib/sikachain/config
```

5. Record **chain ID** (needed for wallet + Anchor):

```bash
curl -s https://rpc.testnet.sikachain.gh/v1/chain/get_info | jq -r .chain_id
```

Spring with `SIKACHAIN=ON` creates privileged account **`sika`** at genesis (not `eosio`).

## Phase 2 — Producer config

1. Copy `config/testnet/nodeos-producer.example.ini` → each BP `config.ini`.
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

**Generate new BP keys** for testnet; do not publish `config/producers-6.json` dev keys:

```bash
cleos create key --to-console   # repeat per BP
# Build config/producers-testnet-6.json with name, pub, pvt
PRODUCERS_JSON=config/producers-testnet-6.json bash scripts/bootstrap-testnet.sh
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

1. `bash scripts/start-hyperion-deps.sh` (ES, Mongo, Redis, RabbitMQ).
2. Configure SHIP → `ws://bp1-internal:8080` in Hyperion `connections.json`.
3. Expose `https://hyperion.testnet.sikachain.gh`.
4. Confirm: `HYPERION_URL=... bash scripts/check-hyperion.sh`

See [hyperion-dev.md](hyperion-dev.md).

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
