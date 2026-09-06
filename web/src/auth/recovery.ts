/** The recovery code: shown once, kept hashed. Crockford base32, five groups. */
import { sha256Hex } from "../db/ids";

const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

export function generateRecoveryCode(): string {
  const bytes = new Uint8Array(20);
  crypto.getRandomValues(bytes);
  let out = "";
  for (let i = 0; i < 18; i++) out += ALPHABET[bytes[i]! % 32];
  const groups = ["NH" + out.slice(0, 2), out.slice(2, 6), out.slice(6, 10), out.slice(10, 14), out.slice(14, 18)];
  return groups.join("-");
}

/** Uppercase, dashes and spaces out, look-alikes folded the Crockford way. */
export function normalizeCode(raw: string): string {
  return raw.toUpperCase().replace(/[\s-]/g, "").replace(/O/g, "0").replace(/[IL]/g, "1");
}

export function hashCode(raw: string): Promise<string> {
  return sha256Hex("nethead-recovery:" + normalizeCode(raw));
}

export async function verifyCode(raw: string, hash: string): Promise<boolean> {
  const got = await hashCode(raw);
  if (got.length !== hash.length) return false;
  let diff = 0;
  for (let i = 0; i < got.length; i++) diff |= got.charCodeAt(i) ^ hash.charCodeAt(i);
  return diff === 0;
}
