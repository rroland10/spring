#!/usr/bin/env bash
# SikaChainDev cleos wrapper — RPC + keosd wallet pre-configured.
#
# Usage:
#   bash scripts/cleos.sh get info
#   bash scripts/cleos.sh transfer sikadev sikauser1 "1.0000 SIKA" "hi" -c sika.token -p sikadev@active
#   bash scripts/cleos.sh                          # print examples
set -euo pipefail
source "$(dirname "$0")/env.sh"

SYS="${SIKA_SYSTEM_ACCOUNT:-sika}"
TOKEN="${SIKA_TOKEN_ACCOUNT:-sika.token}"

if [[ $# -eq 0 ]]; then
  echo "SikaChainDev cleos — RPC ${NODE_URL}  wallet ${WALLET_URL}"
  echo ""
  echo "Start:  bash scripts/start-all.sh   (nodeos + keosd)"
  echo "Wallet: bash scripts/setup-wallet.sh"
  echo "Tests:  bash scripts/test-cleos.sh"
  echo "Docs:   docs/cleos-dev.md"
  echo ""
  echo "Examples:"
  echo "  bash scripts/cleos.sh get info"
  echo "  bash scripts/cleos.sh get account ${SYS}"
  echo "  bash scripts/cleos.sh get currency balance ${TOKEN} sikadev SIKA"
  echo "  bash scripts/cleos.sh system listproducers"
  echo "  bash scripts/cleos.sh transfer sikadev sikauser1 \"1.0000 SIKA\" \"test\" -c ${TOKEN} -p sikadev@active"
  echo "  bash scripts/cleos.sh create account ${SYS} myacct PUB_K1_... PUB_K1_..."
  echo "  bash scripts/cleos.sh system buyrambytes sika.guard myacct 4096 -p sika.guard@active"
  exit 0
fi

cleos_unlock
cleos "$@"
