/**
 * FX attestation signing — must match sika.treas::verify_fx_attestation packing.
 */
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));

function loadAntelope() {
  const appDir =
    process.env.SIKA_APP_DIR || "/Users/randallroland/Desktop/Projects/Sika app";
  const candidates = [
    join(appDir, "node_modules", "@wharfkit", "antelope"),
    join(__dirname, "..", "..", "..", "..", "Sika app", "node_modules", "@wharfkit", "antelope"),
    join(__dirname, "..", "..", "..", "Sika app", "node_modules", "@wharfkit", "antelope"),
  ];
  const require = createRequire(import.meta.url);
  for (const dir of candidates) {
    try {
      return require(dir);
    } catch {
      /* try next */
    }
  }
  throw new Error(
    "@wharfkit/antelope not found — run npm install in Sika app for pushfxsig signing"
  );
}

/** Pack uint64[4] digest input (little-endian). */
export function packFxAttestationParts({ symbol, ppm, ttlSeconds, publishedAtUs }) {
  const buf = Buffer.alloc(32);
  const { Asset } = loadAntelope();
  const symValue = BigInt(Asset.Symbol.from(`4,${symbol}`).code.value.toString());
  buf.writeBigUInt64LE(symValue, 0);
  buf.writeBigUInt64LE(BigInt(ppm), 8);
  buf.writeBigUInt64LE(BigInt(ttlSeconds), 16);
  buf.writeBigUInt64LE(BigInt(publishedAtUs), 24);
  return buf;
}

export function signFxAttestation({ privateKey, symbol, ppm, ttlSeconds, publishedAtUs }) {
  const { Checksum256, PrivateKey } = loadAntelope();
  const parts = packFxAttestationParts({ symbol, ppm, ttlSeconds, publishedAtUs });
  const digest = Checksum256.hash(parts);
  const key =
    typeof privateKey === "string"
      ? PrivateKey.from(privateKey)
      : privateKey;
  const sig = key.signDigest(digest);
  return { digest: String(digest), signature: String(sig), publishedAtUs };
}
