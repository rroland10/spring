#!/usr/bin/env bash
# Pull prebuilt SikaChain nodeos image from GHCR.
#
# Usage:
#   bash sikachaindev/deploy/testnet/pull-image.sh
#   SIKA_NODEOS_IMAGE=ghcr.io/rroland10/sikachain-nodeos:sikachain-dev-sika-v2 bash ...
set -euo pipefail

IMAGE="${SIKA_NODEOS_IMAGE:-ghcr.io/rroland10/sikachain-nodeos:sikachain-dev-sika-v2}"

echo "Pulling ${IMAGE}..."
docker pull --platform linux/amd64 "${IMAGE}"

echo ""
echo "Run from deploy/testnet/:"
echo "  cp .env.example .env   # edit SIGNATURE_PROVIDER + genesis mount"
echo "  docker compose --env-file .env up -d --no-build"
