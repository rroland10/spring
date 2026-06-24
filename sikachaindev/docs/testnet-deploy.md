# SikaChain testnet deploy outline

Ghana v1 wallet launch needs a **public testnet** (or mainnet) with the same protocol shape as SikaChainDev: privileged account **`sika`**, `sika.*` contracts, Savanna finality, SHIP → Hyperion, HTTPS RPC.

**Step-by-step bootstrap:** [testnet-bootstrap.md](testnet-bootstrap.md)

This doc maps dev scripts to production steps. It does not provision cloud infra — use your host (Fly, AWS, bare metal, etc.).

## 1. Build artifacts

| Component | Source | Notes |
|-----------|--------|-------|
| **nodeos / cleos / keosd** | [rroland10/spring](https://github.com/rroland10/spring) tag `sikachain-dev-sika-v2` or newer | `-DSIKACHAIN=ON` (default) — genesis creates **`sika`**, not `eosio`; `cleos get account` uses **`sika.token`** |
| **System contracts** | `sikachain sys contract` | `SIKACHAIN=1 ./build.sh` |
| **eosio.boot** | Spring `unittests/contracts/eosio.boot/` or `build-system-contracts.sh` | Protocol feature activation |
| **sika.msig** | `deploy-msig.sh` pattern | Standard msig WASM @ **`sika.msig`**, privileged |
| **Wallet app** | Sika app | Env from `.env.production.gh-v1.example` |
| **GTM site** | SikaChain | Optional explorer / apply flows |

Local build check:

```bash
bash scripts/check-spring-sikachain.sh
bash scripts/run-contract-tests.sh   # 45 WASM tests @ sika
```

## 2. Genesis and bootstrap

Use **bios boot** (Option 2 in sys contract README), not native chain:

1. Generate genesis with **`sika`** as privileged producer account.
2. Start initial node(s) with Savanna / IF mode enabled.
3. Deploy in order (see `deploy-sika-system.sh`):
   - `sika.token` → create **SIKA** + **CGHS**
   - `sika.system` @ **`sika`** (setcode/setabi on privileged account)
   - Activate protocol features (`eosio.boot`)
   - Init system + satellites (guard, rep, rules, issue, rex, …)
   - `sika.msig` → `setpriv`
4. Register block producers; vote schedule (21 or 6 for lighter testnet).

Dev reference:

```bash
SIKACHAIN_DEV=1 SIKA_RESET_CONFIRM=yes bash scripts/reset-chain.sh -y
bash scripts/bootstrap-dev.sh
bash scripts/bootstrap-6bp.sh          # optional multinode rotation
```

On testnet, replicate the same deploy sequence against your genesis — do not copy SikaChainDev keys or chain ID.

## 3. SHIP + Hyperion (required for wallet Activity)

1. Enable on block producers:
   - `state_history_plugin`
   - `trace-history`, `chain-state-history`, `finality-data-history`
   - `state-history-endpoint` on a reachable host/port (TLS via reverse proxy)
2. Run [Hyperion v2](https://github.com/eosrio/hyperion-history-api) with `connections.json`:
   - `chain` → production chain ID
   - `http` → internal nodeos RPC
   - `ship` → `ws://…` SHIP endpoint
3. Expose Hyperion HTTPS at e.g. `https://hyperion.testnet.sikachain.gh`

Local reference: [hyperion-dev.md](hyperion-dev.md), `start-hyperion.sh`, `setup-hyperion.sh`.

## 4. Public RPC

- HTTPS load balancer → nodeos `chain_api_plugin` (:8888 internally)
- **CORS**: `access-control-allow-origin` for wallet origin, or same-origin API proxy
- Multiple URLs in `NEXT_PUBLIC_CHAIN_READ_RPC_URLS` (comma-separated)
- Savanna finality: clients use `get_transaction_status` / WharfKit finality plugins

## 5. Client configuration

After testnet chain ID and URLs are known:

### Wallet (Vercel / Fly / etc.)

Copy `Sika app/.env.production.gh-v1.example` → hosting env. Set:

- `NEXT_PUBLIC_CHAIN_ID`
- `NEXT_PUBLIC_CHAIN_READ_RPC_URLS`
- `NEXT_PUBLIC_EXPLORER_HYPERION_URL`
- `NEXT_PUBLIC_BASE_URL`
- `NEXT_PUBLIC_CONTRACT_ACCOUNT=sika` (already in template)

Never set `NEXT_PUBLIC_DEV_WALLET=1` in production.

### Anchor custom chain

Edit `anchor-chain.testnet.example.json` (from `sync-dev-env.sh`):

- Replace `REPLACE_WITH_CHAIN_ID`
- Set `nodeUrl` to public HTTPS RPC
- Publish JSON for users (Settings → Blockchains → Add)

### GTM site

Update SikaChain `chain-constants.ts` / env with testnet RPC and Hyperion URLs (`npm run sync:chain` from dev `chain.json` pattern).

## 6. Pre-deploy verification

From a machine that can reach testnet RPC:

```bash
NODE_URL=https://rpc.testnet.sikachain.gh \
  EXPECT_CHAIN_ID=<your-chain-id> \
  HYPERION_URL=https://hyperion.testnet.sikachain.gh \
  bash scripts/verify-testnet.sh
```

Publish Anchor import JSON after URLs are known:

```bash
TESTNET_CHAIN_ID=<chain-id> \
  TESTNET_RPC_URL=https://rpc.testnet.sikachain.gh \
  TESTNET_HYPERION_URL=https://hyperion.testnet.sikachain.gh \
  node scripts/export-anchor-chain.mjs --testnet-example

TESTNET_CHAIN_ID=<chain-id> \
  TESTNET_RPC_URL=https://rpc.testnet.sikachain.gh \
  TESTNET_HYPERION_URL=https://hyperion.testnet.sikachain.gh \
  node scripts/export-testnet-env.mjs   # wallet hosting env
```

Contract + BP bootstrap on fresh genesis:

```bash
bash scripts/bootstrap-testnet.sh   # see docs/testnet-bootstrap.md
```

Legacy one-liner (templates only):

```bash
NODE_URL=https://rpc.testnet.sikachain.gh \
  SIKACHAIN_DEV=1 \
  bash scripts/check-launch-ready.sh
```

Local full stack (dev mirror):

```bash
bash scripts/verify-predeploy.sh
GH_V1=1 bash scripts/verify-predeploy.sh    # + gh-v1 Playwright
FULL=1 bash scripts/verify-predeploy.sh     # + wallet-live (22 tests)
```

Or from Sika app / SikaChain: `npm run verify:predeploy`.

## 7. Post-deploy smoke

See [gh-v1-launch.md](gh-v1-launch.md) section 5:

1. PWA `/app/home` loads
2. Anchor connect on testnet chain ID
3. cGHS balance visible
4. Send 0.01 CGHS
5. Activity shows transfer (Hyperion)
6. Business MSIG propose → approve → exec
7. gh-v1: Swap and Tools hub hidden from menus

## 8. Rollback

Wallet: set `NEXT_PUBLIC_WALLET_ROLLOUT=full` and redeploy — no code change.

Chain upgrades: publish WASM via msig / governance; never rename privileged account off **`sika`** without a coordinated hard fork.

## Related

- [gh-v1-launch.md](gh-v1-launch.md) — Ghana v1 wallet checklist
- [hyperion-dev.md](hyperion-dev.md) — local Hyperion setup
- `sikachaindev/README.md` — dev scripts reference
