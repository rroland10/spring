# cleos + keosd on SikaChainDev

Use **cleos** as the primary CLI for wallet, account creation, transfers, staking, voting, REX, and multisig on the local chain. Governance actions target **`sika`** (system contract). Protocol/native account is **`sikaio`** (not legacy `eosio`).

## Quick start

```bash
cd sikachaindev

# 1. Chain + wallet daemon
bash scripts/start-all.sh          # nodeos :8888 + keosd :8899

# 2. Import dev keys (sika, sikadev, sikauser*, BP keys)
bash scripts/setup-wallet.sh

# 3. Wrapper (auto-unlocks wallet)
bash scripts/cleos.sh get info
bash scripts/cleos.sh get account sika
bash scripts/cleos.sh get currency balance sika.token sikadev SIKA
```

Note: After upgrading Spring, restart nodeos so `cleos get account` resolves **`sika.token`** (not legacy `eosio.token`).

Or export aliases:

```bash
source scripts/env.sh
cleos_unlock
cleos get info
```

## Wallet (keosd)

| Task | Command |
|------|---------|
| Create wallet | `cleos wallet create --file wallet/.password` |
| Unlock | `cleos wallet unlock --password "$(cat wallet/.password)"` |
| Import dev key | `cleos wallet import --private-key 5KQwr...` (see `chain.json`) |
| List keys | `cleos wallet keys` |
| New keypair | `cleos create key --to-console` |

`setup-wallet.sh` creates the **default** wallet, imports the genesis **`sikaio`** key (shared dev key in `chain.json`), all dev accounts, and 6-BP producer keys.

## Account creation

**Recommended (cleos + keosd):**

```bash
bash scripts/create-account-cleos.sh myaccount
# or with existing public key:
bash scripts/create-account-cleos.sh myaccount PUB_K1_...
```

Uses **cleos wallet** for key generation/import. The on-chain `newaccount` + `transfer` + `buyrambytes` bundle uses `create-account.mjs` because RAM must be allocated in the same transaction (cleos `system newaccount` is split-action and still requires explicit stake flags on SikaChain).

After creation, all actions use cleos normally — including **`cleos get account`** once Spring is rebuilt with `default_token_contract_name` (`sika.token`):

```bash
bash scripts/cleos.sh get currency balance sika.token myaccount SIKA
bash scripts/cleos.sh transfer myaccount sikadev "1.0000 SIKA" "hi" -c sika.token -p myaccount@active
```

**Node fallback:** `CREATE_USE_NODE=1 bash scripts/create-account.sh`

## Transfers

```bash
# SIKA
bash scripts/cleos.sh transfer sikadev sikauser1 "1.0000 SIKA" "test" \
  -c sika.token -p sikadev@active

# cGHS stablecoin
bash scripts/cleos.sh transfer sikadev sikauser2 "0.5000 CGHS" "test" \
  -c sika.token -p sikadev@active
```

Fund dev accounts: `bash scripts/create-dev-accounts.sh`

## Stake, vote, REX

```bash
# Delegate bandwidth (example)
bash scripts/cleos.sh system delegatebw sikadev sikadev "10.0000 SIKA" "10.0000 SIKA" false \
  -p sikadev@active

# Vote for block producers (deposit initializes voter row on SikaChain)
bash scripts/cleos.sh push action sika deposit '["sikadev","10.0000 SIKA"]' -p sikadev@active
bash scripts/cleos.sh system voteproducer prods sikadev sikabpa sikabpb sikabpc \
  -p sikadev@active -r 1h

# Vote proxy (Tools → Proxy in app)
bash scripts/cleos.sh push action sika regproxy '["sikauser1",true]' -p sikauser1@active
bash scripts/cleos.sh push action sika delegatebw \
  '["sikauser2","sikauser2","10.0000 SIKA","10.0000 SIKA",false]' -p sikauser2@active
bash scripts/cleos.sh system voteproducer proxy sikauser2 sikauser1 -p sikauser2@active
bash scripts/verify-proxy.sh

# Producer schedule
bash scripts/cleos.sh system listproducers -l 21

# REX (dev cooldown via set-rex-dev-params.sh)
VERIFY_REX=1 bash scripts/verify-rex-unstake.sh
```

## Multisig (`sika.msig`)

Spring **`cleos multisig`** targets **`sika.msig`** on SikaChain builds. You can also use **`cleos push action sika.msig …`** or the helper scripts:

```bash
bash scripts/verify-msig.sh              # sika proposer
bash scripts/verify-msig-business.sh    # sikadev proposer
bash scripts/verify-proxy.sh            # regproxy + voteproducer proxy
bash scripts/msig-propose-transfer.mjs   # propose via Node (cleos approve/exec)
```

Example approve + exec:

```bash
bash scripts/cleos.sh push action sika.msig approve \
  '["sika","myprop",{"actor":"sika","permission":"active"}]' \
  -p sika@active

bash scripts/cleos.sh push action sika.msig exec '["sika","myprop","sika"]' -p sika@active
```

## Tables & queries

```bash
bash scripts/cleos.sh get table sika sika rammarket
bash scripts/cleos.sh get table sika sika rexpool
bash scripts/cleos.sh get table sika sikadev delband
bash scripts/cleos.sh get table sika.treas sika.treas fxquotes
bash scripts/cleos.sh get code sika
```

## Feature test suite (cleos only)

Run the full cleos matrix (queries + transfers + msig):

```bash
bash scripts/test-cleos.sh
VERIFY_REX=1 bash scripts/test-cleos.sh
CREATE_ACCOUNT=1 bash scripts/test-cleos.sh
VERIFY_VOTE=1 bash scripts/test-cleos.sh
bash scripts/test-app-cleos-full.sh   # all app features (vote + REX + MSIG + NFT + RAM)
```

Included in `quick-verify.sh` and `verify-predeploy.sh` by default (`VERIFY_CLEOS=0` or `CLEOS=0` to skip).

## Multinode (6-BP cluster)

When switching from single-node to the 6-BP cluster, `start-bp-cluster.sh` clones chain data from `data/` into `data/multinode/node*/`. If a clone has a **truncated blocks.log** (first block ≠ 1), replay fails — the script auto-detects this and re-clones.

```bash
ENABLE_SHIP=1 bash scripts/start-6bp-cluster.sh
bash scripts/stop-bp-cluster.sh    # graceful stop + .clean_shutdown markers
BP_CLUSTER_REFRESH=1 bash scripts/start-6bp-cluster.sh   # force full re-clone
```

After upgrading Spring (`cleos` / `nodeos`), restart producers so RPC serves `sika.token` for `get account`.

## Environment

| Variable | Default |
|----------|---------|
| `NODE_URL` | `http://127.0.0.1:8888` |
| `WALLET_URL` | `http://127.0.0.1:8899` |
| `SIKA_SYSTEM_ACCOUNT` | `sika` |
| `SIKA_TOKEN_ACCOUNT` | `sika.token` |
| `CLEOS` | `../build/programs/cleos/cleos` |

## Related

- `scripts/cleos.sh` — wrapper with auto-unlock
- `scripts/setup-wallet.sh` — keosd bootstrap
- `scripts/test-cleos.sh` — automated cleos feature gate
- `docs/gh-v1-launch.md` — wallet app rollout (Anchor / PWA)
