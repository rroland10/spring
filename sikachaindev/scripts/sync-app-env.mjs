#!/usr/bin/env node
/**
 * Sync Sika app env files from sikachaindev/chain.json (+ accounts JSON for system account).
 *
 *   node sync-app-env.mjs           # default + phase3 templates
 *   node sync-app-env.mjs --local   # also copy default → Sika app/.env.local
 */
import { readFileSync, writeFileSync, copyFileSync, existsSync } from "fs";
import { dirname, join, resolve } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");
const APP_DIR = process.env.SIKA_APP_DIR ?? "/Users/randallroland/Desktop/Projects/Sika app";

const chain = JSON.parse(readFileSync(join(ROOT, "chain.json"), "utf8"));
const accountsDefault = JSON.parse(readFileSync(join(ROOT, "accounts.json"), "utf8"));
const accountsPhase3 = JSON.parse(readFileSync(join(ROOT, "accounts.phase3.json"), "utf8"));

function envBlock({ systemAccount, accountsMeta, label, devWallet = false, walletRollout = null }) {
  const hyperion = chain.hyperionUrl?.trim();
  const hyperionLine = hyperion
    ? `NEXT_PUBLIC_EXPLORER_HYPERION_URL=${hyperion}`
    : "# NEXT_PUBLIC_EXPLORER_HYPERION_URL=http://127.0.0.1:7000";

  const devWalletBlock = devWallet
    ? `
# Dev-only: WharfKit in-browser wallet for local sikadev testing (never on mainnet)
NEXT_PUBLIC_DEV_WALLET=1
NEXT_PUBLIC_E2E_MOCK_ACTOR=sikadev
NEXT_PUBLIC_E2E_MOCK_PRIVATE_KEY=${chain.accounts?.sikadev?.privateKey ?? ""}

# Dev swap: SIKA ↔ CGHS via token hub (local stand-in for bridge token)
NEXT_PUBLIC_BRIDGE_TOKEN_CONTRACT=${chain.tokenContract ?? "sika.token"}
NEXT_PUBLIC_BRIDGE_TOKEN_SYMBOL=CGHS
NEXT_PUBLIC_BRIDGE_TOKEN_PRECISION=4
`
    : "";

  return `# ${label}
# Synced from spring/sikachaindev/chain.json — run: bash scripts/sync-app-env.mjs
# Preferred chain env keys (NEXT_PUBLIC_CHAIN_*); EOS-prefixed keys kept for compatibility.

NEXT_PUBLIC_APP_NAME=Sika App
NEXT_PUBLIC_MARKET=gh
${walletRollout ? `NEXT_PUBLIC_WALLET_ROLLOUT=${walletRollout}` : "# NEXT_PUBLIC_WALLET_ROLLOUT=gh-v1  # Accra-first beta surface"}
NEXT_PUBLIC_BASE_URL=${chain.appUrl ?? "http://127.0.0.1:3003"}
NEXT_PUBLIC_CHAIN_RPC_PROTOCOL=http
NEXT_PUBLIC_CHAIN_RPC_HOST=127.0.0.1
NEXT_PUBLIC_CHAIN_RPC_PORT=8888
NEXT_PUBLIC_CHAIN_READ_RPC_URLS=${chain.url ?? "http://127.0.0.1:8888"}
NEXT_PUBLIC_CHAIN_ID=${chain.chainId}
NEXT_PUBLIC_CHAIN_NAME=${chain.chainName ?? "SikaChainDev"}
NEXT_PUBLIC_EOS_RPC_PROTOCOL=http
NEXT_PUBLIC_EOS_RPC_HOST=127.0.0.1
NEXT_PUBLIC_EOS_RPC_PORT=8888
NEXT_PUBLIC_EOS_READ_RPC_URLS=${chain.url ?? "http://127.0.0.1:8888"}
NEXT_PUBLIC_EOS_CHAIN_ID=${chain.chainId}
NEXT_PUBLIC_EOS_NAME=${chain.chainName ?? "SikaChainDev"}
NEXT_PUBLIC_CONTRACT_ACCOUNT=${systemAccount}
NEXT_PUBLIC_PROTOCOL_ACCOUNT=${chain.protocolAccount ?? "sikaio"}
NEXT_PUBLIC_TABLE_ACCOUNT=${systemAccount}
NEXT_PUBLIC_SYSTEM_CONTRACT_DISPLAY_NAME=${accountsMeta.systemDisplayName ?? chain.systemContractDisplayName ?? "SikaChain System"}
NEXT_PUBLIC_TOKEN_CONTRACT=${chain.tokenContract ?? accountsMeta.token}
NEXT_PUBLIC_REX_CONTRACT=${chain.rexContract ?? accountsMeta.rex}
NEXT_PUBLIC_MSIG_CONTRACT=${chain.msigContract ?? accountsMeta.msigContract ?? accountsMeta.msig}
NEXT_PUBLIC_ATOMICASSETS_CONTRACT=${chain.atomicassetsContract ?? "atomicassets"}
NEXT_PUBLIC_TOKEN_SYMBOL=${chain.symbol ?? accountsMeta.symbol}
NEXT_PUBLIC_TOKEN_PRECISION=4
NEXT_PUBLIC_BP_AVAILABLE_CHAIN=sikachain
NEXT_PUBLIC_STABLECOIN_CONTRACT=${chain.tokenContract ?? "sika.token"}
NEXT_PUBLIC_STABLECOIN_SYMBOL=CGHS
NEXT_PUBLIC_STABLECOIN_PRECISION=4
NEXT_PUBLIC_WEBSITE_URL=${chain.websiteUrl ?? "http://127.0.0.1:3004"}
NEXT_PUBLIC_WEBSITE_LOCALE=en
${hyperionLine}
# Optional: hosted WharfKit web authenticator (browser sign-in without Anchor install)
# NEXT_PUBLIC_WEB_AUTHENTICATOR_URL=https://auth.sikachain.gh
${devWalletBlock}`;
}

const defaultPath = join(APP_DIR, ".env.sikachaindev");
const phase3Path = join(APP_DIR, ".env.sikachaindev.phase3");
const ghV1Path = join(APP_DIR, ".env.sikachaindev.gh-v1");
const localPath = join(APP_DIR, ".env.local");

writeFileSync(
  defaultPath,
  envBlock({
    systemAccount: accountsDefault.system ?? chain.systemContract ?? "sika",
    accountsMeta: accountsDefault,
    label: "Sika Chain Dev — local Spring node",
  }),
  "utf8",
);
console.log("Wrote", defaultPath);

writeFileSync(
  phase3Path,
  envBlock({
    systemAccount: accountsPhase3.system ?? "sika",
    accountsMeta: accountsPhase3,
    label: "SikaChain Dev Phase 3 — Spring -DSIKACHAIN=ON (protocol sikaio + system sika)",
    devWallet: true,
  }),
  "utf8",
);
console.log("Wrote", phase3Path);

writeFileSync(
  ghV1Path,
  envBlock({
    systemAccount: accountsPhase3.system ?? "sika",
    accountsMeta: accountsPhase3,
    label: "SikaChain Dev — Ghana v1 rollout (gh-v1 surface + dev wallet)",
    devWallet: true,
    walletRollout: "gh-v1",
  }),
  "utf8",
);
console.log("Wrote", ghV1Path);

const prodGhV1Path = join(APP_DIR, ".env.production.gh-v1.example");
writeFileSync(
  prodGhV1Path,
  `# Ghana v1 production / testnet — copy to hosting provider env (Vercel, Fly, etc.)
# Do NOT commit real secrets. Replace placeholders before deploy.
# Generate fresh dev templates: bash spring/sikachaindev/scripts/sync-dev-env.sh

NEXT_PUBLIC_APP_NAME=Sika App
NEXT_PUBLIC_MARKET=gh
NEXT_PUBLIC_WALLET_ROLLOUT=gh-v1
NEXT_PUBLIC_BASE_URL=https://app.sikachain.gh

NEXT_PUBLIC_CHAIN_READ_RPC_URLS=https://rpc.testnet.sikachain.gh
NEXT_PUBLIC_CHAIN_ID=REPLACE_WITH_CHAIN_ID
NEXT_PUBLIC_CHAIN_NAME=SikaChain

NEXT_PUBLIC_CONTRACT_ACCOUNT=sika
NEXT_PUBLIC_PROTOCOL_ACCOUNT=sikaio
NEXT_PUBLIC_TABLE_ACCOUNT=sika
NEXT_PUBLIC_SYSTEM_CONTRACT_DISPLAY_NAME=SikaChain System
NEXT_PUBLIC_TOKEN_CONTRACT=sika.token
NEXT_PUBLIC_REX_CONTRACT=sika.rex
NEXT_PUBLIC_MSIG_CONTRACT=sika.msig
NEXT_PUBLIC_ATOMICASSETS_CONTRACT=atomicassets
NEXT_PUBLIC_TOKEN_SYMBOL=SIKA
NEXT_PUBLIC_TOKEN_PRECISION=4
NEXT_PUBLIC_BP_AVAILABLE_CHAIN=sikachain
NEXT_PUBLIC_STABLECOIN_CONTRACT=sika.token
NEXT_PUBLIC_STABLECOIN_SYMBOL=CGHS
NEXT_PUBLIC_STABLECOIN_PRECISION=4

NEXT_PUBLIC_WEBSITE_URL=https://sikachain.com
NEXT_PUBLIC_WEBSITE_LOCALE=en
NEXT_PUBLIC_EXPLORER_HYPERION_URL=https://hyperion.testnet.sikachain.gh

# Sign-in: Anchor (default) and/or hosted web authenticator
# NEXT_PUBLIC_WEB_AUTHENTICATOR_URL=https://auth.sikachain.gh

# Never set on production:
# NEXT_PUBLIC_DEV_WALLET=1
# NEXT_PUBLIC_E2E_MOCK_ACTOR=...
# NEXT_PUBLIC_E2E_MOCK_PRIVATE_KEY=...
`,
  "utf8",
);
console.log("Wrote", prodGhV1Path);

if (process.argv.includes("--local")) {
  const src =
    process.env.SIKACHAIN_DEV === "1" && existsSync(phase3Path)
      ? phase3Path
      : defaultPath;
  copyFileSync(src, localPath);
  console.log("Copied", src, "→", localPath);
}
