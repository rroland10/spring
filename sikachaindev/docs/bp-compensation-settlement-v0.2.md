# BP Compensation & Multi-Country Settlement v0.2

Status tracker for SikaChainDev. On-chain host: **`sika`** (Phase 3, `-DSIKACHAIN=ON`) or **`eosio`** (legacy); both run sika.system WASM. Settlement: `sika.treas`.

## Architecture

```
Local fees (CGHS, …) → sika.treas::accruefee / sweep
                              ├─ reserve (CUSD) ──→ paycost (Tier-1 BP)
                              ├─ credyield ──→ rexpool.cghs_yield_pool
                              └─ accrueepoch ──→ Tier-2 inflation bucket

Tier-2: claimprod → vest (SIKA) → claimvest → REX
FX: fxquotes (setfx governance | pushfx sika.oracle)
```

## On-chain surface

| Contract | Actions |
|----------|---------|
| `sika.treas` | `init`, `setparams`, `setfx`, `pushfx`, `pushfxsig`, `setoraclekey`, `setmarketpref`, `accruefee`, `sweep`, `paycost`, `creditreserve`, `subsidize`, `rebalance`, `clearyield` |
| `sika.system` | `claimprod`, `claimvest`, `setvesting`, `accrueepoch`, `credyield`, `claimrexyld`, `refillpay` |

## Dev tooling

| Script | Purpose |
|--------|---------|
| `build-sika-contracts-docker.sh` | Build all WASMs |
| `upgrade-contracts.sh` | Publish WASM to running node |
| `oracle-push-fx.mjs` | Live FX via `pushfx` (optional HMAC attestation when `ORACLE_ATTEST_SECRET` set) |
| `settlement-sweep.sh` / `settlement-worker.mjs` | Accrue + sweep worker (dev cron) |
| `settlement-bullmq-worker.mjs` | Production worker (BullMQ + `REDIS_URL`) |
| `seed-marketprefs.mjs` | §6.4 per-market payout prefs on-chain |
| `validate-settlement-params.mjs` | §10 on-chain param audit vs dev defaults |
| `model-settlement-economics.mjs` | §10 volume / reserve runway model |
| `set-rex-dev-params.sh` | Dev: shorten REX unstake cooldown (`setrexcfg`) |
| `verify-rex-unstake.sh` | Smoke: buyrex → sellrex → refund |
| `verify-settlement-v0.2.sh` | Smoke test (oracle, sweep, subsidize, claimprod) |
| `verify-tier2-vesting.sh` | Tier-2 vest path |

Unit tests: `make sika_unit_tests && ./sikachain-tests/sika_unit_tests --run_test=sika_treas_tests`

## §10 — Illustrative parameters (dev defaults)

These are **not final economics**; they seed SikaChainDev and the test suite.

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `sweep_slice_bps` | 2500 (25%) | Share of accrued local fees (CUSD ref) moved on each `sweep` |
| `fee_to_yield_bps` | 2500 (25%) | Of swept CUSD, credited to `rexpool.cghs_yield_pool` via `credyield` |
| Reserve remainder | 75% | Swept CUSD not sent to yield → `reserve.cusd_balance` |
| `cost_recovery_cusd` | 250 CUSD | Tier-1 daily BP pay (`paycost` per `claimprod`) |
| `max_subsidy_per_market_bps` | 500 (5%) | Cap on cross-market `subsidize` vs donor fee base |
| `reserve_gold_bps` | 3000 (30%) | Target gGOLD share on `rebalance` |
| Tier-2 `bonus_vesting_seconds` | 60 (dev) / 7d (prod target) | Vesting cliff for usage-gated SIKA |
| FX TTL (`pushfx`) | 3600s | Oracle quote freshness; `0` = no expiry (`setfx` peg) |
| Dev peg fallback | 1_000_000 ppm | 1 CGHS = 1 CUSD when `fxquotes` row missing |

## Remaining (post v0.2 scaffold)

- Governance sign-off using [settlement-economics-v0.2.md](./settlement-economics-v0.2.md) checklist

## §6.4 — Per-market payout prefs

| Layer | Implementation |
|-------|----------------|
| On-chain | `marketpref` table + `setmarketpref`; `clearyield` / `claimrexyld(..., market)` enforce menu |
| App | `MarketConfig.payoutPrefs` + `checkMarketReadiness()` in `markets/compliance.ts` |
| Dev seed | `seed-marketprefs.mjs` — gh: local+gGOLD; ng: local-only until compliance |

Default dev prefs: `gh:CGHS:0:1:1` (gGOLD allowed, cUSD blocked), `ng:CNGN:0:0:0`.

## Production settlement worker (BullMQ)

```bash
cd sikachaindev/scripts && npm install   # optional: bullmq + ioredis
REDIS_URL=redis://127.0.0.1:6379 SETTLEMENT_CRON='0 */6 * * *' \
  node settlement-bullmq-worker.mjs
```

Dev fallback: `settlement-worker.mjs` (setInterval / `SETTLEMENT_ONCE=1`).

## App — REX yield claim (§6.4 UI)

When `NEXT_PUBLIC_STABLECOIN_*` is set, the Earn → Rewards tab:

- Computes claimable share from `rexpool.cghs_yield_pool`
- Shows payout picker (local / gGOLD / cUSD) gated by `checkMarketReadiness()`
- Submits `claimrewards` (local) or `claimrexyld(..., market)` on-chain
- Stake: `eosio::buyrex`; unstake: `sellrex` → `refund` after cooldown

See [settlement-economics-v0.2.md](./settlement-economics-v0.2.md) for §10 modelling.

### REX unstake (configurable cooldown)

Governance action `eosio::setrexcfg` sets `rexcfg.unstake_seconds` (default 7 days). Dev deploy sets **60s** via `set-rex-dev-params.sh`.

On-chain user payout: `sika.treas::setpayoutpref` (owner auth, §6.4 gated).

## Ricardian contracts (wallet signing UX)

User-facing Earn actions ship with Ricardian clauses embedded in the ABI at build time:

| Contract | Actions with Ricardian |
|----------|------------------------|
| `sika.system` | REX, vote, stake, RAM, proxy — see `verify-ricardian.mjs` (15 actions) |
| `sika.treas` | `setpayoutpref`, `clearyield` |
| `sika.token` | `transfer`, `open`, `issue` |

Source: `contracts/sika.system/ricardian/` and `contracts/sika.treas/ricardian/` (CDT `target_ricardian_directory`).

```bash
bash sikachaindev/scripts/build-sika-contracts-docker.sh
node sikachaindev/scripts/verify-ricardian.mjs
bash sikachaindev/scripts/upgrade-contracts.sh   # publish ABIs to chain
```

Wallets (Anchor / WharfKit) render the YAML+Markdown template when the on-chain ABI includes `ricardian_contract`. Governance/ops actions remain unsigned summaries for now.

App bindings (Contract Kit, Ricardian embedded in generated ABIs):

```bash
# Local ABIs (works offline after contract build)
SIKA_BINDINGS_LOCAL=1 bash sikachaindev/scripts/generate-bindings.sh

# Or from running node
bash sikachaindev/scripts/generate-bindings.sh
```

Earn page transacts via `rexContractActions.ts` → Contract Kit `Action[]` with bundled ABI (includes Ricardian text before deploy sync).

## Oracle attestation (`pushfxsig`)

| Action | Auth | Purpose |
|--------|------|---------|
| `setoraclekey` | governance | Store `attest_key`; optional `require_signed_push` blocks legacy `pushfx` |
| `pushfxsig` | ECDSA signature | Updates `fxquotes` when signature matches packed `(symbol, ppm, ttl, published_at)` |
| `pushfx` | `sika.oracle` | Dev fallback when signed push not required |

Dev setup:

```bash
ORACLE_SIGN_KEY=PVT_K1_... node sikachaindev/scripts/setup-oracle-key.mjs
ORACLE_SIGN_KEY=PVT_K1_... node sikachaindev/scripts/oracle-push-fx.mjs

# Pre-mainnet smoke — fail if legacy pushfx is used:
ORACLE_REQUIRE_SIGNED=1 ORACLE_SIGN_KEY=PVT_K1_... bash sikachaindev/scripts/verify-settlement-v0.2.sh
```

## Contract fixes (v0.2.1)

- **`buyrex`** now transfers SIKA → `sika.rex` before minting REX shares (no separate `deposit` required).
- **`apply_rex_stake`** treats `total_rex == 0` as first mint (RAM-fee `compound_rex_sika` can leave lendable SIKA without REX shares).
