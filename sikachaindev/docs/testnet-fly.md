# Testnet deploy — Docker and Fly.io

Containerized **nodeos** for the first public testnet BP. Pair with [testnet-bootstrap.md](testnet-bootstrap.md) for genesis and contract steps.

## Layout

```
sikachaindev/deploy/testnet/
  Dockerfile.nodeos          # runtime image (linux/amd64 nodeos binary)
  entrypoint.sh              # envsubst config + start nodeos
  nodeos-producer.docker.ini # container config template
  docker-compose.yml         # local / VPS single-BP
  fly.toml.example           # Fly.io app template
  build-image.sh             # docker build wrapper
```

## 1. Build nodeos (Linux amd64)

### Option A — GitHub Actions (recommended)

Push a tag or run workflow manually:

```bash
git tag sikachain-dev-sika-v3 && git push fork sikachain-dev-sika-v3
# or: Actions → "SikaChain testnet nodeos image" → Run workflow
```

Image: `ghcr.io/rroland10/sikachain-nodeos:<tag>` (also `:latest`).

Pull in `docker-compose.yml` or Fly:

```yaml
image: ghcr.io/rroland10/sikachain-nodeos:sikachain-dev-sika-v2
```

### Option B — Local / CI build

The Docker image **copies** `build/programs/nodeos/nodeos` — it does not compile Spring inside the container.

On **Linux** or CI:

```bash
git checkout sikachain-dev-sika-v2
bash sikachaindev/scripts/build-sikachain-spring.sh
bash sikachaindev/deploy/testnet/build-image.sh
```

On **macOS**: build in a Linux VM/GitHub Actions, or use `docker buildx` with a Linux builder. Do not copy a macOS `nodeos` binary into the image.

## 2. Genesis

1. Generate keys: `cleos create key --to-console`
2. Edit `config/testnet/genesis.example.json` → set `initial_key`, `initial_timestamp`
3. Mount at run time: `-v ./genesis.json:/etc/sikachain/genesis.json:ro`

## 3. Docker Compose (VPS / local)

```bash
# Set producer signing key in docker-compose.yml environment
export SIGNATURE_PROVIDER='PUB_K1_xxx=KEY:5K...'

docker compose -f sikachaindev/deploy/testnet/docker-compose.yml up -d
curl http://127.0.0.1:8888/v1/chain/get_info
```

Persistent chain data: Docker volume `sikachain_data`.

## 4. Fly.io

Fly suits **HTTPS RPC** and **SHIP** exposure. **P2P (9876)** between BPs often works better on a VPS with static IPs; use Fly for BP1 RPC + history or as a read API node.

```bash
cp sikachaindev/deploy/testnet/fly.toml.example fly.toml
# Edit app name, region, P2P_ADVERTISE, CORS_ORIGIN

fly apps create sikachain-testnet-bp1
fly volumes create sikachain_data --region iad --size 50

fly secrets set SIGNATURE_PROVIDER='PUB_K1_xxx=KEY:5K...'

# Optional: custom genesis
# fly secrets set SIKA_GENESIS_JSON="$(cat genesis.json)"

fly deploy
fly certs add rpc.testnet.sikachain.gh   # if using custom domain + http_service
```

Public RPC URL after deploy: `https://<app>.fly.dev` (or custom domain via `fly certs`).

**Memory:** start with **4 GB** VM — replay and WASM need headroom.

## 5. After nodeos is up

From ops machine with genesis `sika` key:

```bash
export NODE_URL=https://<your-rpc>
bash scripts/bootstrap-testnet.sh
```

Publish clients:

```bash
TESTNET_CHAIN_ID=$(curl -s $NODE_URL/v1/chain/get_info | jq -r .chain_id) \
  TESTNET_RPC_URL=https://rpc.testnet.sikachain.gh \
  node scripts/export-testnet-env.mjs
```

Verify:

```bash
NODE_URL=... EXPECT_CHAIN_ID=... HYPERION_URL=... bash scripts/verify-testnet.sh
```

## 6. TLS / nginx alternative

For bare metal, use `config/testnet/nginx-rpc.example.conf` in front of `127.0.0.1:8888`.

## Security

- Never commit `SIGNATURE_PROVIDER` private keys — use Fly secrets or Docker env files gitignored
- Generate **new** BP keys for testnet; do not reuse `producers-6.json` dev keys
- Restrict `CORS_ORIGIN` to `https://app.sikachain.gh` in production

## Related

- [testnet-bootstrap.md](testnet-bootstrap.md) — full runbook
- [testnet-deploy.md](testnet-deploy.md) — component map
- [hyperion-dev.md](hyperion-dev.md) — indexer after SHIP is exposed
