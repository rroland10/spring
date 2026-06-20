# SikaChainDev

Local single-node Spring chain for SikaChain development (`sika.system` @ `eosio`, `sika.token`, satellites).

## Quick start

```bash
bash scripts/dev-ready.sh
```

Starts nodeos/keosd, deploys contracts if needed, funds `sikadev`, regenerates WharfKit bindings, and syncs `Sika app/.env.local`.

## Scripts

| Script | Purpose |
|--------|---------|
| `dev-ready.sh` | All-in-one dev prep |
| `bootstrap-dev.sh` | Start chain + deploy + `sikadev` |
| `reset-chain.sh -y` | Wipe data/wallet (fresh genesis) |
| `upgrade-contracts.sh` | Publish WASM only (no re-issue) |
| `deploy-sika-system.sh` | Full bootstrap deploy |
| `generate-bindings.sh` | WharfKit types → `Sika app/src/contracts/` |
| `run-contract-tests.sh` | 40 Spring BOOST tests |
| `start-app.sh` | Start Sika App wallet UI (:3003) |
| `start-web.sh` | Start SikaChain GTM site (:3004) |
| `check-health.sh` | RPC + SIKA + `sikadev` + optional app/site (exit code) |
| `build-system-contracts.sh` | Build `eosio.boot` for feature activation |

## Prerequisites

- Spring built at `../build` (`nodeos`, `cleos`, `keosd`)
- Sika contract WASMs at `../../sikachain sys contract/contracts/build/contracts/`
- `eosio.boot` ships with Spring at `../unittests/contracts/eosio.boot/` (or build via `build-system-contracts.sh`)

## Dev accounts

Keys in `chain.json`. After bootstrap:

- **eosio** — privileged system account (~1B SIKA)
- **sikadev** — wallet UI test account (10,000 SIKA)

Import `sikadev` in Anchor: RPC `http://127.0.0.1:8888`, chain ID in `.env.sikachaindev`.

## App

Sika wallet UI runs on **port 3003** (not 3000 — that port may be used by other local apps).

```bash
bash scripts/start-app.sh
# → http://127.0.0.1:3003
```

## Marketing site (SikaChain)

GTM site — genesis program, block explorer, producer apply, admin dashboard — on **port 3004**.

```bash
bash scripts/start-web.sh
# → http://127.0.0.1:3004
```

Repo: [github.com/rroland10/SikaChain](https://github.com/rroland10/SikaChain). Sync chain constants: `npm run sync:chain` in that project after editing `chain.json` here.

After starting chain, site, and app: `cd` to the SikaChain repo and run `npm run verify:stack` (all five endpoints).

## Tests

```bash
bash scripts/run-contract-tests.sh
```

## Phase 3 — privileged account `sika` (optional)

Default dev chain uses Spring’s standard privileged account **`eosio`** hosting `sika.system` WASM.

To use **`sika`** as the chain-native system account:

```bash
# 1. Rebuild Spring with SIKACHAIN=ON
bash scripts/build-sikachain-spring.sh

# 2. Rebuild contracts with SIKACHAIN=1
cd "sikachain sys contract/contracts" && SIKACHAIN=1 ./build.sh

# 3. Reset + bootstrap with Phase 3 env
export SIKACHAIN_DEV=1
SIKA_RESET_CONFIRM=yes bash scripts/reset-chain.sh
bash scripts/bootstrap-dev.sh
```

Also update `Sika app/.env.local`: `NEXT_PUBLIC_CONTRACT_ACCOUNT=sika` and `NEXT_PUBLIC_TABLE_ACCOUNT=sika`.

Without `-DSIKACHAIN=ON`, nodeos always creates `eosio` at genesis regardless of config.ini.
