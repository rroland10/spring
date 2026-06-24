#!/usr/bin/env node
/**
 * Propose a token transfer via sika.msig (cleos multisig hardcodes eosio.msig).
 *
 * Usage:
 *   node msig-propose-transfer.mjs <proposer> <proposal_name> <to> <quantity> [memo]
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const proposer = process.argv[2];
const proposalName = process.argv[3];
const to = process.argv[4];
const quantity = process.argv[5];
const memo = process.argv[6] ?? "msig verify";
const rpc = process.argv[7] || process.env.NODE_URL || "http://127.0.0.1:8888";

const msigAccount = process.env.MSIG_ACCOUNT || "sika.msig";
const tokenContract = process.env.SIKA_TOKEN_ACCOUNT || "sika.token";
const appDir =
  process.env.SIKA_APP_DIR || "/Users/randallroland/Desktop/Projects/Sika app";
const contractsDir =
  process.env.SIKA_CONTRACTS_DIR ||
  "/Users/randallroland/Desktop/Projects/sikachain sys contract/contracts";

if (!proposer || !proposalName || !to || !quantity) {
  console.error(
    "Usage: msig-propose-transfer.mjs <proposer> <proposal_name> <to> <quantity> [memo] [rpc]",
  );
  process.exit(1);
}

const wharf = await import(
  pathToFileURL(join(appDir, "node_modules/@wharfkit/antelope/lib/antelope.js")).href
);
const {
  ABI,
  Action,
  APIClient,
  Asset,
  Name,
  PermissionLevel,
  PrivateKey,
  SignedTransaction,
  TimePointSec,
  Transaction,
  UInt16,
  UInt32,
  UInt8,
  VarUInt,
  Bytes,
  Serializer,
} = wharf;

const tokenAbi = ABI.from(
  JSON.parse(
    readFileSync(
      join(contractsDir, "build/contracts/sika.token/sika.token.abi"),
      "utf8",
    ),
  ),
);

const msigAbiPath =
  process.env.MSIG_ABI_PATH ||
  join(__dirname, "../.msig-build", msigAccount, `${msigAccount}.abi`);
const msigAbi = ABI.from(JSON.parse(readFileSync(msigAbiPath, "utf8")));

const chainJson = JSON.parse(readFileSync(join(__dirname, "../chain.json"), "utf8"));

function resolvePrivateKey(account) {
  const systemAccount =
    process.env.SIKA_SYSTEM_ACCOUNT || chainJson.systemContract || "sika";
  if (account === systemAccount && process.env.SIKA_SYSTEM_PRIVATE_KEY) {
    return PrivateKey.from(process.env.SIKA_SYSTEM_PRIVATE_KEY);
  }
  const fromAccount = chainJson.accounts?.[account]?.privateKey;
  if (fromAccount) {
    return PrivateKey.from(fromAccount);
  }
  return PrivateKey.from(chainJson.privateKey);
}

const privateKey = resolvePrivateKey(proposer);
const client = new APIClient({ url: rpc });

const level = PermissionLevel.from({ actor: proposer, permission: "active" });
const transferData = Serializer.encode({
  abi: tokenAbi,
  type: "transfer",
  object: {
    from: Name.from(proposer),
    to: Name.from(to),
    quantity: Asset.from(quantity),
    memo,
  },
});

const info = await client.v1.chain.get_info();
const header = info.getTransactionHeader(3600);

const proposeAction = Action.from(
  {
    account: msigAccount,
    name: "propose",
    authorization: [{ actor: proposer, permission: "active" }],
    data: {
      proposer: Name.from(proposer),
      proposal_name: Name.from(proposalName),
      requested: [level],
      trx: {
        ...header,
        delay_sec: VarUInt.from(0),
        context_free_actions: [],
        actions: [
          {
            account: Name.from(tokenContract),
            name: Name.from("transfer"),
            authorization: [level],
            data: transferData,
          },
        ],
        transaction_extensions: [],
      },
    },
  },
  msigAbi,
);

const tx = Transaction.from({
  ...header,
  actions: [proposeAction],
});

const digest = tx.signingDigest(info.chain_id);
const sig = privateKey.signDigest(digest);
const signed = SignedTransaction.from({ ...tx, signatures: [sig] });
const result = await client.v1.chain.send_transaction(signed);
console.log(`Proposed ${proposalName} on ${msigAccount}`);
console.log(`tx: ${result.transaction_id}`);

const deadline = Date.now() + 120_000;
while (Date.now() < deadline) {
  const res = await fetch(`${rpc}/v1/chain/get_table_rows`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      json: true,
      code: msigAccount,
      scope: proposer,
      table: "proposal",
      lower_bound: proposalName,
      upper_bound: proposalName,
      limit: 1,
    }),
  });
  const data = await res.json();
  if (data.rows?.length) {
    break;
  }
  await new Promise((r) => setTimeout(r, 500));
}
