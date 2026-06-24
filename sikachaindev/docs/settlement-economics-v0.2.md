# Settlement economics model (§10)

Illustrative workbook for BP compensation v0.2. **Not financial advice** — parameters must be reviewed against real volume, FX, and regulatory constraints before mainnet.

## What the model answers

| Question | Output field |
|----------|----------------|
| Does daily fee revenue cover Tier-1 BP cost? | `tier1.coverageRatioDaily` |
| How long does the bootstrap reserve last? | `tier1.reserveCoverageDaysAtCurrentSweep` |
| What daily fee volume breaks even? | `tier1.breakEvenDailyFeeVolumeCusdRef` |
| How much reaches REX yield pool? | `rexYield.dailyYieldPoolCusdRef` |

## Assumptions (defaults)

- **Peg:** 1 local stable unit ≈ 1 CUSD reference (`MODEL_CUSD_PPM=1000000`)
- **On-chain params:** read live from `sika.treas` when node is up; else script uses dev defaults
- **Tier-1:** `cost_recovery_cusd × MODEL_BPS` (default 21 BPs × 250 CUSD = 5,250 CUSD/day)
- **Sweep:** `sweep_slice_bps` of accrued fees; split by `fee_to_yield_bps` to REX vs reserve

## Scenarios

| `MODEL_SCENARIO` | Description |
|------------------|-------------|
| `gh_pilot` | 50k CGHS/day network fees (default) |
| `gh_scale` | 500k CGHS/day |
| `gh_ng_launch` | Ghana + Nigeria launch volumes |
| `multi_market` | Gh + Ng + Tz |

Custom volumes:

```bash
MODEL_GH_DAILY_CGHS=250000 MODEL_NG_DAILY_CNGN=100000 MODEL_BPS=21 \
  node sikachaindev/scripts/model-settlement-economics.mjs
```

## Commands

```bash
# Audit on-chain params vs dev defaults
node sikachaindev/scripts/validate-settlement-params.mjs

# Run economics model (chain + scenario)
node sikachaindev/scripts/model-settlement-economics.mjs

MODEL_SCENARIO=gh_ng_launch node sikachaindev/scripts/model-settlement-economics.mjs

# Enforce signed oracle in CI / pre-mainnet smoke:
ORACLE_REQUIRE_SIGNED=1 ORACLE_SIGN_KEY=PVT_K1_... bash sikachaindev/scripts/verify-settlement-v0.2.sh
```

## Illustrative scenario results (dev params, 21 BPs)

Run against live `sika.treas` reserve (~38k CUSD at last dev deploy). **Tier-1 cost** = 21 × 250 = **5,250 CUSD/day**.

| Scenario | Daily fees (CUSD ref) | Tier-1 coverage | Reserve runway (days) | Break-even volume | REX yield pool/day |
|----------|----------------------|-----------------|----------------------|-------------------|-------------------|
| `gh_pilot` | 50k | 1.8× | ~4 | 28k | 3,125 |
| `gh_scale` | 500k | 17.9× | 0 (self-sustaining) | 28k | 31,250 |
| `gh_ng_launch` | 350k | 12.5× | 0 | 28k | 21,875 |
| `multi_market` | 600k | 21.4× | 0 | 28k | 37,500 |

Interpretation:

- **Break-even** depends only on `cost_recovery_cusd` and BP count — not on volume.
- **Runway** hits 0 once daily reserve inflow (75% of swept fees) exceeds bootstrap reserve; pilot volumes still extend runway ~4 days at 50k/day.
- **Coverage** above 1× means fee sweep alone covers Tier-1 BP opex at the modelled volume.

Re-run after changing on-chain params or reserve balance:

```bash
node sikachaindev/scripts/model-settlement-economics.mjs | jq '.tier1, .rexYield'
```

## Sign-off checklist (governance)

- [ ] Volume assumptions validated per market (MoMo / hub settlement throughput)
- [ ] `cost_recovery_cusd` benchmarked against real BP opex (USD)
- [ ] `sweep_slice_bps` + `fee_to_yield_bps` balance reserve vs REX consumer yield
- [ ] Bootstrap reserve depletion curve acceptable at Year-1 volumes
- [ ] `inflation_gain` (Tier-2 k) modelled against `epoch_fee_revenue`
- [ ] FX oracle + `max_subsidy_per_market_bps` reviewed with legal
- [ ] Per-market `allowed_payout_currencies` signed off (§6.4)

## Related

- [bp-compensation-settlement-v0.2.md](./bp-compensation-settlement-v0.2.md) — architecture & dev tooling
- Original spec §10–§11 — open questions (FX liquidity, regulatory gates, peg cascade)
