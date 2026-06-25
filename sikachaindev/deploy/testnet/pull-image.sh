#!/usr/bin/env bash
# Pull prebuilt SikaChain nodeos image from GHCR.
#
# Usage:
#   bash sikachaindev/deploy/testnet/pull-image.sh
#   SIKA_NODEOS_IMAGE=ghcr.io/rroland10/sikachain-nodeos:sikachain-dev-sika-v5 bash ...
set -euo pipefail

IMAGE="${SIKA_NODEOS_IMAGE:-ghcr.io/rroland10/sikachain-nodeos:sikachain-dev-sika-v5}"

echo "Pulling ${IMAGE}..."
if ! docker pull --platform linux/amd64 "${IMAGE}"; then
  echo ""
  echo "Pull failed. Common causes:"
  echo "  - GHA build still running (Actions → SikaChain testnet nodeos image)"
  echo "  - GHCR package is private — docker login ghcr.io or make package public"
  exit 1
fi

echo ""
echo "Run from deploy/testnet/:"
echo "  bash up.sh   # gen keys + auto .env + compose up"
echo "  # or manually:"
echo "  cp .env.example .env   # edit SIGNATURE_PROVIDER + SIKA_GENESIS_HOST"
echo "  docker compose --env-file .env up -d --no-build"
