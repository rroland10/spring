#!/usr/bin/env node
/**
 * Normalize Antelope public keys to PUB_K1_ (preferred) or legacy EOS format.
 * Uses WharfKit from Sika app when available; falls back to cleos for conversion.
 */
import {readFileSync} from 'node:fs'
import {dirname, join} from 'node:path'
import {fileURLToPath} from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const appDir =
  process.env.SIKA_APP_DIR || '/Users/randallroland/Desktop/Projects/Sika app'

async function loadPublicKey() {
  const mod = await import(
    new URL(
      join(appDir, 'node_modules/@wharfkit/antelope/lib/antelope.js'),
      import.meta.url,
    ).href,
  )
  return mod.PublicKey
}

export async function toPubK1(key) {
  const trimmed = String(key || '').trim()
  if (!trimmed) return ''
  if (trimmed.startsWith('PUB_K1_')) return trimmed
  const PublicKey = await loadPublicKey()
  return PublicKey.from(trimmed).toString()
}

export async function toLegacy(key) {
  const trimmed = String(key || '').trim()
  if (!trimmed) return ''
  if (trimmed.startsWith('EOS')) return trimmed
  const PublicKey = await loadPublicKey()
  return PublicKey.from(trimmed).toLegacyString()
}

function usage() {
  console.error('Usage: key-format.mjs to-pub-k1 <key> | to-legacy <key>')
  process.exit(1)
}

const [cmd, key] = process.argv.slice(2)
if (!cmd || !key) usage()

if (cmd === 'to-pub-k1') {
  console.log(await toPubK1(key))
} else if (cmd === 'to-legacy') {
  console.log(await toLegacy(key))
} else {
  usage()
}
