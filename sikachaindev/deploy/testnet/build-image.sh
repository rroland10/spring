#!/usr/bin/env bash
# Build linux/amd64 nodeos runtime image for testnet deploy.
#
# Requires nodeos built for Linux amd64 at build/programs/nodeos/nodeos.
# On macOS: use a Linux VM/CI, or docker buildx with --platform linux/amd64 after
# building inside a Linux builder container.
#
# Usage:
#   bash sikachaindev/deploy/testnet/build-image.sh
#   bash sikachaindev/deploy/testnet/build-image.sh --push REGISTRY/sikachain-nodeos:testnet
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
IMAGE="${SIKA_NODEOS_IMAGE:-sikachain-nodeos:testnet}"
PUSH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push) PUSH="$2"; shift 2 ;;
    *) echo "unknown arg: $1"; exit 1 ;;
  esac
done

NODEOS="${ROOT}/build/programs/nodeos/nodeos"
if [[ ! -x "${NODEOS}" ]]; then
  echo "error: ${NODEOS} not found — build Spring first:"
  echo "  git checkout sikachain-dev-sika-v2"
  echo "  bash sikachaindev/scripts/build-sikachain-spring.sh"
  exit 1
fi

echo "=== build testnet nodeos image ==="
echo "  context: ${ROOT}"
echo "  image:   ${IMAGE}"
echo ""

docker build \
  -f "${SCRIPT_DIR}/Dockerfile.nodeos" \
  --platform linux/amd64 \
  -t "${IMAGE}" \
  "${ROOT}"

if [[ -n "${PUSH}" ]]; then
  docker tag "${IMAGE}" "${PUSH}"
  docker push "${PUSH}"
  echo "Pushed ${PUSH}"
fi

echo ""
echo "Run: docker compose -f sikachaindev/deploy/testnet/docker-compose.yml up"
