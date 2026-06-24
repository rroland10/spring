# SikaChainDev

Local single-node Spring chain for Sika Chain development. **`sika.system` @ `sika`** is the privileged system account (`sika.null`, `sika.prods`). Token: **SIKA** + **CGHS** on `sika.token`, plus satellite contracts.

## cleos CLI (wallet + on-chain testing)

Primary CLI for transfers, account creation, stake, vote, REX, and msig. See **[docs/cleos-dev.md](docs/cleos-dev.md)**.

```bash
bash scripts/start-all.sh              # nodeos + keosd
bash scripts/setup-wallet.sh           # import sika + dev keys
bash scripts/cleos.sh get info         # wrapper (auto-unlock)
bash scripts/test-cleos.sh              # full cleos feature matrix
bash scripts/test-app-cleos-full.sh     # all app features (vote+REX+MSIG+NFT+RAM+vesting opt)
VERIFY_REX=1 bash scripts/test-cleos.sh
bash scripts/create-account-cleos.sh myacct
```

## Quick start (Phase 3)

Run in **your local terminal** (keeps nodeos alive):

```bash
export SIKACHAIN_DEV=1 SIKA_SYSTEM_ACCOUNT=sika ENABLE_SHIP=1
cd sikachaindev
bash scripts/launch-ecosystem.sh --verify   # detached — survives terminal close
# or interactively:
bash scripts/start-ecosystem.sh --quick --verify
```

Stop with `bash scripts/stop-ecosystem.sh`.

Chain-only prep (no apps):

```bash
bash scripts/dev-ready.sh
```

Starts nodeos/keosd, deploys contracts if needed, funds `sikadev` with SIKA and CGHS, regenerates WharfKit bindings, and syncs `Sika app/.env.local`.

## Scripts

| Script | Purpose |
|--------|---------|
| `dev-ready.sh` | All-in-one dev prep |
| `launch-ecosystem.sh` | Detached start (survives shell exit) — `--verify`, `--full`; uses `daemonize.sh` on macOS |
| `start-ecosystem.sh` | Chain + Hyperion + wallet + site + API (use in a local terminal) |
| `ensure-adapter.sh` | Restore wharfkit adapter from `sikachain-stack.tar.gz` if incomplete |
| `sync-dev-env.sh` | Sync app + adapter + website from `chain.json` |
| `smoke-phase3.sh` | Fast read-only smoke (health + Phase 3 + Hyperion) |
| `verify-all.sh` | Full gate: Spring SIKACHAIN + smoke + contract tests (`VERIFY_DEV=1` for on-chain) |
| `test-features.sh` | Feature matrix: chain, settlement, apps, Hyperion (`ON_CHAIN=1` for txs; `WALLET_UI=1` for Playwright) |
| `ensure-wallet-app.sh` | Probe / restart :3003 when business group routes 404 (Playwright reuse) |
| `test-wallet-ui.sh` | Playwright live-chain tests (WharfKit dev wallet / `sikadev`) |
| `test-wallet-msig.sh` | Playwright live MSIG propose → approve → exec (`MSIG_CLEANUP=1` default) |
| `setup-biz-msig-dev.sh` | Create `sikamsig1` (2-of-3 linked active) for business import E2E |
| `test-wallet-live.sh` | UI + MSIG + business import Playwright gate (`ON_CHAIN_SEND=1` default) |
| `test-wallet-gh-v1.sh` | Ghana v1 rollout surface (isolated :3099, `gh-v1` gating) |
| `verify-gh-v1.sh` | Env template + gh-v1 Playwright gate |
| `check-launch-ready.sh` | Offline + live sika/gh-v1 readiness (`LIVE=1` adds Playwright; `FULL=1` adds wallet-live) |
| `cleos.sh` | cleos wrapper — auto-unlock keosd, RPC/wallet defaults (see **docs/cleos-dev.md**) |
| `test-cleos.sh` | Feature matrix via cleos (transfers, tables, msig; `VERIFY_REX=1`) |
| `test-app-cleos-full.sh` | Full app parity via cleos (vote deposit, REX, business MSIG, NFT; `VERIFY_TIER2=1`) |
| `create-account-cleos.sh` | New account via `cleos system newaccount` + buyrambytes |
| `setup-wallet.sh` | Create/unlock default keosd wallet; import dev/BP keys |
| `export-anchor-chain.mjs` | Regenerate `anchor-chain.json` + `anchor-chain.testnet.example.json` from `chain.json` |
| `verify-testnet.sh` | Remote smoke: `sika` + `sika.token` + Hyperion (`NODE_URL`, `EXPECT_CHAIN_ID`) |
| `verify-testnet-stack.sh` | Full local docker gate (verify + cleos + features + client export) |
| `verify-predeploy-remote.sh` | Templates + `verify-testnet` + optional hosted app/site URLs |
| `bootstrap-testnet.sh` | Deploy contracts + BPs on fresh testnet genesis (not dev chain id) |
| `bootstrap-docker-testnet.sh` | One-shot docker testnet on `:18890` (contracts + BPs, producer `sika`) |
| `export-testnet-env.mjs` | Generate wallet production env from `TESTNET_*` vars |
| `export-testnet-client-config.sh` | Anchor JSON + app env from live testnet RPC |
| `deploy/testnet/` | Docker + Fly.io nodeos templates — [docs/testnet-fly.md](docs/testnet-fly.md) |
| `setup-hyperion-testnet.sh` | Hyperion for hosted testnet — [docs/testnet-hyperion.md](docs/testnet-hyperion.md) |
| `setup-hyperion-testnet-local.sh` | Hyperion for local docker testnet (API `:7002`) |
| `smoke-wallet.sh` | Wallet UI RPC probes for `sikadev` (balances, stake, REX, NFTs) |
| `wait-for-rpc.sh` | Block until nodeos RPC is up (default 360s; replay-safe) |
| `stop-ecosystem.sh` | Stop chain + Node apps (`--hyperion` to stop indexer containers) |
| `bootstrap-dev.sh` | Start chain + deploy + fund `sikadev` |
| `create-dev-accounts.sh` | Create + fund `sikadev`, `sikauser1`, `sikauser2` (keys in `chain.json`) |
| `smoke-dev-accounts.sh` | RPC smoke for all dev accounts in `chain.json` |
| `verify-peer-transfer.sh` | On-chain `sikadev` → `sikauser1` transfer smoke (`PEER_SYMBOL=CGHS` for stablecoin) |
| `verify-stack.sh` | Full gate: `verify-all` + feature matrix + Playwright (`VERIFY_UI=1` default) |
| `quick-verify.sh` | Daily gate: smoke-phase3 + Hyperion + 6-BP rotation + `test-cleos` (`VERIFY_CLEOS=0` to skip txs) |

Browser RPC reads require CORS on nodeos — `config/config.ini` sets `access-control-allow-origin = *`. Restart nodeos after changing config (`bash scripts/stop-node.sh && bash scripts/start-node.sh --daemon`).

| `reset-chain.sh -y` | Wipe data/wallet (fresh genesis) |
| `upgrade-system-abi.sh` | Patch + publish `delband` on `sika.system` ABI (wallet stake queries) |
| `ensure-system-abi.sh` | Auto-fix delband ABI on bootstrap if missing |
| `patch-system-abi.mjs` | Merge native table defs from `eosio.system.abi` into build artifact |
| `upgrade-contracts.sh` | Publish WASM only (no re-issue; includes `sika.treas` when built) |
| `deploy-sika-system.sh` | Full bootstrap deploy (SIKA + CGHS create) |
| `generate-bindings.sh` | WharfKit types → `Sika app/src/contracts/` |
| `run-contract-tests.sh` | 45 Spring BOOST tests (requires `-DSIKACHAIN=ON` for Phase 3) |
| `start-app.sh` | Start Sika app wallet UI (:3003) |
| `start-web.sh` | Start Sika Chain GTM site (:3004) |
| `check-health.sh` | RPC + tokens + Phase 3 tables (rammarket, rexpool) + optional app/site |
| `deploy-msig.sh` | Build upstream msig WASM, deploy as `sika.msig`, `setpriv`, verify |
| `verify-msig.sh` | Propose → approve → exec smoke test (`sika` proposer) |
| `verify-msig-business.sh` | Same flow with `sikadev` proposer |
| `cleanup-msig-proposals.sh` | Cancel stale open proposals for dev proposers (default `sikadev`) |
| `verify-settlement-v0.2.sh` | Settlement scaffold + msig step |
| `verify-dev.sh` | Ricardian + settlement + economics (+ optional REX/tier-2) |
| `cleanup-legacy-msig.sh` | Deprivilege and clear unused `eosio.msig` after `sika.msig` is live |
| `sync-app-env.mjs` | Regenerate `Sika app/.env.sikachaindev` (+ phase3) from `chain.json` |
| `bootstrap-phase3.sh` | Phase 3 reset + bootstrap (`sika` system account) |
| `verify-phase3.sh` | Checks privileged `sika` hosts sika.system (requires `SIKACHAIN_DEV=1`) |
| `check-hyperion.sh` | Smoke-test Hyperion when `hyperionUrl` is set in `chain.json` |
| `start-hyperion-deps.sh` | Docker: ES, Mongo, Redis, RabbitMQ for Hyperion |
| `setup-hyperion.sh` | Generate Hyperion connection config for SikaChainDev |
| `deploy-atomicassets.sh` | Build + deploy `atomicassets` NFT contract |
| `verify-atomicassets.sh` | Check AtomicAssets WASM + init |
| `mint-nft-dev.sh` | Mint sample NFT to `sikadev` |
| `restart-ship.sh` | Stop/start nodeos with SHIP + replay (fixes stale nodeos) |
| `check-ship.sh` | Verify SHIP on :8080 |
| `check-spring-sikachain.sh` | Report if Spring built with `-DSIKACHAIN=ON` |
| `build-system-contracts.sh` | Build `eosio.boot` for feature activation |
| `bootstrap-21bp.sh` | Register + vote 21 producers (`sikabpa`–`sikabpu`) on running chain |
| `bootstrap-6bp.sh` | Register/vote 6 producers + wait for on-chain schedule promotion |
| `ensure-producer-schedule.sh` | Wait for voted BPs to appear in active/pending schedule (needs upgraded `sika.system`) |
| `upgrade-contracts.sh` | Publish latest Sika WASM (run after `sika.system` changes) |
| `start-6bp-cluster.sh` | Run **6** nodeos instances for rotation testing |
| `reconfigure-6bp-cluster.sh` | Fast restart: rewrite configs (CORS/SHIP/P2P) without re-cloning |
| `ensure-bp-cluster-healthy.sh` | Detect stalled multinode chain; resume producers or reconfigure |
| `BP_CLUSTER_REFRESH=1 start-6bp-cluster.sh` | Re-clone chain state into multinode dirs (fixes fork/LIB drift) |
| `start-6bp-lite.sh` | Single node as `sikabpa` + 6-BP schedule (default for app/vote UI dev) |
| `start-2bp-cluster.sh` | 2 nodeos processes (minimal multinode rotation attempt) |
| `start-21bp-cluster.sh` | Run 21 nodeos instances for full schedule rotation |
| `stop-bp-cluster.sh` | Stop multinode cluster; restart single node with `start-node.sh` |
| `vote-bp-schedule.sh` | Align all producer votes to N active BPs (default 6) |

## Multisig (`sika.msig`)

Governance multisig is deployed as **`sika.msig`** (standard Spring `eosio.msig` WASM, privileged). `bootstrap-dev.sh` deploys it automatically when missing or not privileged.

```bash
bash scripts/deploy-msig.sh
bash scripts/verify-msig.sh
bash scripts/verify-msig-business.sh
bash scripts/cleanup-msig-proposals.sh   # cancel stale dev proposals (optional)
bash scripts/setup-biz-msig-dev.sh       # sikamsig1 for import-from-chain E2E
bash scripts/test-wallet-msig.sh         # Playwright propose → approve → exec
bash scripts/test-wallet-live.sh         # UI + MSIG + business import gate
```

The Sika app Business → Msigs pages use `NEXT_PUBLIC_MSIG_CONTRACT=sika.msig`. Spring **`cleos multisig`** still hardcodes `eosio.msig` — use the app, WharfKit, `cleos push action sika.msig …`, or `scripts/msig-propose-transfer.mjs`.

Full dev verification:

```bash
bash scripts/verify-dev.sh
# VERIFY_REX=1 bash scripts/verify-dev.sh   # includes REX cooldown wait
```

## Ghana v1 launch

Accra-first wallet surface (`NEXT_PUBLIC_WALLET_ROLLOUT=gh-v1`). See **[docs/gh-v1-launch.md](docs/gh-v1-launch.md)** for production env, verification commands, and post-deploy smoke.

```bash
bash scripts/check-launch-ready.sh        # templates + on-chain phase 3 (if RPC up)
bash scripts/verify-predeploy.sh        # launch-ready + test-cleos + stack URLs (CLEOS=0 to skip)
GH_V1=1 bash scripts/verify-predeploy.sh # + gh-v1 Playwright
FULL=1 bash scripts/verify-predeploy.sh  # + full wallet-live (slow)

LIVE=1 bash scripts/check-launch-ready.sh # + verify-gh-v1 Playwright only
FULL=1 bash scripts/check-launch-ready.sh # + full wallet-live gate (slow)

bash scripts/verify-gh-v1.sh              # env template + Playwright gh-v1 gate
bash scripts/preview-gh-v1.sh             # local gh-v1 wallet preview (sync + .env.local)
bash scripts/test-wallet-live.sh          # live UI + MSIG + import (20 tests)
GH_V1=1 bash scripts/test-wallet-live.sh  # + gh-v1 rollout (22 tests)
```

Production env template: `Sika app/.env.production.gh-v1.example` (generated by `sync-dev-env.sh`).

## History (Hyperion)

Transaction **Activity** in the wallet requires **Hyperion v2**. Bootstrap starts backing services automatically; finish indexer setup with `setup-hyperion.sh`, then verify:

```bash
bash scripts/wallet-ready.sh   # RPC + dev accounts + Hyperion
```

See [docs/hyperion-dev.md](docs/hyperion-dev.md).

```bash
bash scripts/restart-ship.sh          # enable SHIP on nodeos (:8080)
bash scripts/start-hyperion-deps.sh   # Elasticsearch, MongoDB, Redis, RabbitMQ
bash scripts/setup-hyperion.sh        # writes hyperion/config/*.json
```

## Prerequisites

- Spring built at `../build` (`nodeos`, `cleos`, `keosd`)
- Sika contract WASMs at `../../sikachain sys contract/contracts/build/contracts/`
- `eosio.boot` ships with Spring at `../unittests/contracts/eosio.boot/` (or build via `build-system-contracts.sh`)

## Dev accounts

Keys in `chain.json`. After bootstrap (Phase 3 / `SIKACHAIN_DEV=1`):

- **sika** — privileged system account (~1B SIKA), block producer
- **sikadev** — wallet UI test account (10,000 SIKA, 2,500 CGHS)
- **sikauser1** / **sikauser2** — peer wallets for send/receive tests (5,000 SIKA, 500 CGHS each)
- **sika.issue** — CGHS issuer (same dev key as sika)

Create and fund all dev accounts:

```bash
bash scripts/create-dev-accounts.sh
```

Legacy mode (`SIKACHAIN_DEV=0`) is deprecated — Spring genesis always creates **`sika`** as the privileged account.

Import `sikadev` in **Anchor** for local signing:

1. **Add chain** — Settings → Blockchains → Add custom chain (or import `anchor-chain.json` from this repo — refreshed by `sync-dev-env.sh`)  
   - Name: `SikaChainDev`  
   - Chain ID: `9b2fde923758593c09517f77ed445a3962a9c938f44405dac43b4ccfebbfa57e`  
   - RPC: `http://127.0.0.1:8888`  
2. **Import key** — use `sikadev` private key from `chain.json` (dev only).

The Sika app shows as **Sika** in Anchor sign prompts (ESR `appName`). Protocol remains standard WharfKit + ESR.

The Sika app reads CGHS via `NEXT_PUBLIC_STABLECOIN_*` in `.env.sikachaindev` — home balance shows **cGHS** when configured.

### Dev wallet (no Anchor required)

Phase 3 env (`.env.sikachaindev.phase3`) enables **`NEXT_PUBLIC_DEV_WALLET=1`**: a **Dev wallet (sikadev)** button on `/app/home` signs in-browser with the local dev key from `chain.json`. Use only on SikaChainDev — never on mainnet.

Manual walkthrough at http://127.0.0.1:3003/app/home:

| Screen | Flow |
|--------|------|
| Home | Dev wallet or Anchor → balance card |
| Send / Receive | Transfer SIKA or CGHS |
| Earn | REX lend / unstake |
| Vote | Vote for BPs |
| Business | Create / approve msig proposal |
| Explore | Account history via Hyperion |

Automated UI tests (live RPC + Hyperion):

```bash
# Isolated Playwright server on :3099 (recommended)
bash scripts/test-wallet-ui.sh

# Or against app already on :3003
PLAYWRIGHT_REUSE_SERVER=1 bash scripts/test-wallet-ui.sh

# Full feature matrix (read-only probes)
bash scripts/test-features.sh

# On-chain settlement + 16 Playwright tests (includes UI send sikadev → sikauser1)
ON_CHAIN=1 WALLET_UI=1 PLAYWRIGHT_REUSE_SERVER=1 bash scripts/test-features.sh

# Fast read-only check (no txs, no browser)
bash scripts/quick-verify.sh

# Everything: Spring build, contract tests, verify-dev, feature matrix, Playwright
bash scripts/verify-stack.sh
```

In the Sika app repo:

```bash
npm run test:wallet:live      # UI + MSIG live gate (chain + app on :3003)
npm run test:wallet:gh-v1     # Ghana v1 rollout surface (isolated :3099)
npm run test:e2e:live:full    # live-chain only, includes on-chain CGHS send
GH_V1=1 npm run test:wallet:live   # live gate + gh-v1 rollout spec
```

Ghana beta env: `bash scripts/preview-gh-v1.sh` then start the app (or `sync-dev-env.sh` + copy `.env.sikachaindev.gh-v1`).

## App

Sika app (wallet UI) runs on **port 3003** (not 3000 — that port may be used by other local apps).

```bash
bash scripts/start-app.sh
# → http://127.0.0.1:3003
```

Nigeria marketing preview (copy only): `http://127.0.0.1:3003/ng`

## Marketing site (Sika Chain)

GTM site — genesis program, block explorer, producer apply, admin dashboard — on **port 3004**.

```bash
bash scripts/start-web.sh
# → http://127.0.0.1:3004
```

Repo: [github.com/rroland10/SikaChain](https://github.com/rroland10/SikaChain). Sync chain constants: `npm run sync:chain` in that project after editing `chain.json` here.

After starting chain, site, and app: `cd` to the SikaChain repo and run `npm run verify:stack` (all five endpoints).

## 21 block producers (testing)

Default dev chain runs a **single node** (`sika` producer on `:8888`). For vote-page / producer-ranking tests you can register a full top-21 set without running 21 processes:

```bash
# Chain must be up (bootstrap-dev.sh or start-all.sh)
bash scripts/bootstrap-21bp.sh
cleos system listproducers -l 21
```

Producer accounts `sikabpa` … `sikabpu` and dev keys live in `config/producers-21.json`. Each producer self-stakes SIKA (the system account funds them; it cannot self-stake on `sika.token`). All 21 vote for the full producer set so the schedule fills.

The single node runs as **`sikabpa`** with `enable-stale-production` (plus a genesis `sika` fallback key for schedule handoff). After `sika.system` promotes voted BPs via `set_proposed_producers`, blocks keep advancing on one node — sufficient for Sika app **Vote** UI and explorer producer tables.

`sika.system` must include `update_elected_producers` (see `sika.system/src/voting_schedule.cpp`). Upgrade a running chain with:

```bash
bash scripts/upgrade-contracts.sh
bash scripts/ensure-producer-schedule.sh
```

For **real block rotation** (each BP signs in turn), bootstrap producers first, then:

**6 producers (recommended for dev):**

```bash
bash scripts/bootstrap-6bp.sh           # register + vote sikabpa–sikabpf
bash scripts/start-6bp-lite.sh        # single node + 6-BP schedule (wallet/vote UI)
bash scripts/start-6bp-cluster.sh     # 6 nodeos processes (real rotation; ~6× RAM)
bash scripts/verify-6bp-rotation.sh    # confirm producers rotate
bash scripts/ensure-bp-cluster-healthy.sh  # recover if head block stalls
bash scripts/stop-bp-cluster.sh       # stop multinode; returns to single-node
```

Producer accounts `sikabpa` … `sikabpf` are in `config/producers-6.json` (subset of `producers-21.json`).
All 21 remain registered on chain; `vote-bp-schedule.sh` limits the active schedule to 6.

**21 producers (optional, heavy):**

```bash
bash scripts/bootstrap-21bp.sh
bash scripts/start-21bp-cluster.sh
```

The cluster clones chain state into `data/multinode/` (~heavy on disk/RAM). Re-run `bootstrap-21bp.sh` after a fresh `reset-chain.sh`.

## Tests

```bash
bash scripts/run-contract-tests.sh
bash scripts/quick-verify.sh
VERIFY_REX=1 VERIFY_TIER2=1 VERIFY_DEV=1 bash scripts/verify-all.sh
VERIFY_REX=1 VERIFY_TIER2=1 VERIFY_DEV=1 VERIFY_UI=1 VERIFY_WEB=1 bash scripts/verify-stack.sh
```

## Phase 3 — privileged account `sika`

With Spring built `-DSIKACHAIN=ON`, the genesis privileged account is **`sika`** (not `eosio`). Contracts must be built with `SIKACHAIN=1`.

```bash
bash scripts/check-spring-sikachain.sh   # confirm SIKACHAIN=ON
bash scripts/bootstrap-phase3.sh --reset # fresh chain + deploy + app env
bash scripts/verify-phase3.sh
```

Daily dev (existing chain):

```bash
export SIKACHAIN_DEV=1 SIKA_SYSTEM_ACCOUNT=sika ENABLE_SHIP=1
bash scripts/start-ecosystem.sh --quick
VERIFY_ATOMICASSETS=1 bash scripts/verify-dev.sh
bash scripts/run-contract-tests.sh     # 45 in-process WASM tests
```

Without `-DSIKACHAIN=ON`, nodeos creates `eosio` at genesis — use legacy `accounts.json` and `.env.sikachaindev` (not `.phase3`).
