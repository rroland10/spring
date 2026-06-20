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
| `check-health.sh` | RPC + SIKA + `sikadev` probe (exit code) |
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

```bash
cd "../../Sika app"
npm run dev
```

## Tests

```bash
bash scripts/run-contract-tests.sh
```

## Phase 3 (deferred)

Spring `config.hpp` still uses `system_account_name = "eosio"`. Sika contracts run on `eosio`; renaming to `sika` requires a Spring fork + genesis change.
