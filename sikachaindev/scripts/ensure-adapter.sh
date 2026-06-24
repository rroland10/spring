#!/usr/bin/env bash
# Restore wharfkit adapter from sikachain-stack.tar.gz when package.json is missing.
#
# Usage:
#   bash scripts/ensure-adapter.sh
#   SIKA_ADAPTER_DIR=/path/to/adapter bash scripts/ensure-adapter.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/env.sh"

ADAPTER_DIR="${SIKA_ADAPTER_DIR:-/Users/randallroland/Desktop/Projects/wharfkit adapter}"
TAR="${ADAPTER_DIR}/sikachain-stack.tar.gz"

if [[ -f "${ADAPTER_DIR}/package.json" ]]; then
  exit 0
fi

if [[ ! -f "${TAR}" ]]; then
  echo "error: adapter incomplete — no package.json and no ${TAR}" >&2
  echo "  set SIKA_ADAPTER_DIR to a full wharfkit adapter checkout" >&2
  exit 1
fi

echo "Restoring wharfkit adapter from sikachain-stack.tar.gz..."

ENV_BACK=""
EXAMPLE_BACK=""
if [[ -f "${ADAPTER_DIR}/.env" ]]; then
  ENV_BACK="$(mktemp)"
  cp "${ADAPTER_DIR}/.env" "${ENV_BACK}"
fi
if [[ -f "${ADAPTER_DIR}/.env.example" ]]; then
  EXAMPLE_BACK="$(mktemp)"
  cp "${ADAPTER_DIR}/.env.example" "${EXAMPLE_BACK}"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
tar -xzf "${TAR}" -C "${TMP}" sikachain/backend

# Merge extracted backend; keep tarball as canonical tree (routes/, services/, prisma/).
rsync -a "${TMP}/sikachain/backend/" "${ADAPTER_DIR}/"

[[ -n "${ENV_BACK}" ]] && cp "${ENV_BACK}" "${ADAPTER_DIR}/.env"
[[ -n "${EXAMPLE_BACK}" ]] && cp "${EXAMPLE_BACK}" "${ADAPTER_DIR}/.env.example"

# start-ecosystem uses `npm run dev`
if ! grep -q '"dev":' "${ADAPTER_DIR}/package.json" 2>/dev/null; then
  python3 - <<'PY' "${ADAPTER_DIR}/package.json"
import json, sys
path = sys.argv[1]
pkg = json.load(open(path))
scripts = pkg.setdefault("scripts", {})
scripts.setdefault("dev", scripts.get("dev:api", "tsx watch src/api/index.ts"))
json.dump(pkg, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
fi

# Prisma 7 schema uses preview names unavailable in 5.x (dev pin).
if [[ -f "${ADAPTER_DIR}/prisma/schema.prisma" ]]; then
  sed -i '' 's/fullTextSearchPostgres/fullTextSearch/g' "${ADAPTER_DIR}/prisma/schema.prisma" 2>/dev/null || \
    sed -i 's/fullTextSearchPostgres/fullTextSearch/g' "${ADAPTER_DIR}/prisma/schema.prisma"
fi

echo "Installing adapter dependencies (first run may take a minute)..."
(
  cd "${ADAPTER_DIR}"
  # Prisma 7.x needs Node >=20.19; pin 5.x for broader dev machines.
  npm install --no-fund --no-audit \
    prisma@5.22.0 @prisma/client@5.22.0 --save-exact
  npm install --no-fund --no-audit
  npx prisma generate
)

node "${SCRIPT_DIR}/sync-adapter-env.mjs"

echo "Adapter restored at ${ADAPTER_DIR}"
