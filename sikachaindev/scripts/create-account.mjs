#!/usr/bin/env node
/**
 * Create a SikaChainDev account (newaccount + buyrambytes in one transaction).
 */
import {readFileSync} from 'node:fs'
import {dirname, join} from 'node:path'
import {fileURLToPath, pathToFileURL} from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))

const account = process.argv[2]
const publicKey = process.argv[3]
const ramBytes = Number(process.argv[4] || 4096)
const rpc = process.argv[5] || 'http://127.0.0.1:8888'
const appDir =
  process.env.SIKA_APP_DIR || '/Users/randallroland/Desktop/Projects/Sika app'
const contractsDir =
  process.env.SIKA_CONTRACTS_DIR ||
  '/Users/randallroland/Desktop/Projects/sikachain sys contract/contracts'

if (!account || !publicKey) {
  console.error('Usage: create-account.mjs <name> <public-key> [ram-bytes] [rpc-url]')
  process.exit(1)
}

const wharf = await import(
  pathToFileURL(join(appDir, 'node_modules/@wharfkit/antelope/lib/antelope.js')).href
)
const {ABI, Action, APIClient, Asset, Name, PrivateKey, PublicKey, SignedTransaction, Transaction} = wharf

const tokenAbi = ABI.from(
  JSON.parse(
    readFileSync(
      join(contractsDir, 'build/contracts/sika.token/sika.token.abi'),
      'utf8',
    ),
  ),
)

const systemAbi = ABI.from(
  JSON.parse(
    readFileSync(
      join(contractsDir, 'build/contracts/sika.system/sika.system.abi'),
      'utf8',
    ),
  ),
)

const chainJson = JSON.parse(readFileSync(join(__dirname, '../chain.json'), 'utf8'))
const privateKey = PrivateKey.from(chainJson.privateKey)
const pubK1 = PublicKey.from(publicKey).toString()
const client = new APIClient({url: rpc})

const auth = {
  threshold: 1,
  keys: [{key: pubK1, weight: 1}],
  accounts: [],
  waits: [],
}

const info = await client.v1.chain.get_info()

try {
  await client.v1.chain.get_account(Name.from(account))
  console.log(`Account ${account} already exists — skipping create`)
  process.exit(0)
} catch {
  // account missing — proceed
}

// eosio cannot pay for RAM after sika.system deploy (buyram transfers SIKA to self).
// sika.rep rejects SIKA deposits — use sika.guard as fee payer.
const ramPayer = process.env.RAM_PAYER || 'sika.guard'
const ramCost = Asset.from('100.0000 SIKA')

const actions = [
  Action.from(
    {
      account: 'eosio',
      name: 'newaccount',
      authorization: [{actor: 'eosio', permission: 'active'}],
      data: {
        creator: 'eosio',
        name: account,
        owner: auth,
        active: auth,
      },
    },
    systemAbi,
  ),
  Action.from(
    {
      account: 'sika.token',
      name: 'transfer',
      authorization: [{actor: 'eosio', permission: 'active'}],
      data: {
        from: 'eosio',
        to: ramPayer,
        quantity: ramCost,
        memo: `RAM for ${account}`,
      },
    },
    tokenAbi,
  ),
  Action.from(
    {
      account: 'eosio',
      name: 'buyrambytes',
      authorization: [{actor: ramPayer, permission: 'active'}],
      data: {
        payer: ramPayer,
        receiver: account,
        bytes: ramBytes,
      },
    },
    systemAbi,
  ),
]

const header = info.getTransactionHeader(120)

const tx = Transaction.from({
  ...header,
  actions,
})

const digest = tx.signingDigest(info.chain_id)
const sig = privateKey.signDigest(digest)
const signed = SignedTransaction.from({...tx, signatures: [sig]})

const result = await client.v1.chain.send_transaction(signed)
console.log(`Created ${account} (${ramBytes} bytes RAM)`)
console.log(`tx: ${result.transaction_id}`)
