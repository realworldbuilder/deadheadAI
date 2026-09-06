/**
 * Sign in with Apple. Apple hands the browser or the app an identity token
 * (a JWT signed by Apple); we check the signature against Apple's published
 * keys, the issuer, the audience (the web Services ID or the app's bundle
 * id) and our own nonce, then find or make the head behind that Apple ID.
 */
import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from "jose";
import { parseHandle } from "./handles";
import { generateRecoveryCode, hashCode } from "./recovery";
import { isoPlus, nowIso, randomToken, sha256Hex, uuid } from "../db/ids";
import { one, stmt } from "../db/notes";

export const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEYS_URL = new URL("https://appleid.apple.com/auth/keys");
export const NONCE_TTL_SECONDS = 300;

let keyGetter: JWTVerifyGetKey | null = null;

/** Tests hand in a local key; production fetches Apple's JWKS (cached by jose). */
export function configureAppleKeys(getter: JWTVerifyGetKey | null): void {
  keyGetter = getter;
}

function keys(): JWTVerifyGetKey {
  if (!keyGetter) keyGetter = createRemoteJWKSet(APPLE_KEYS_URL, { cacheMaxAge: 24 * 3600 * 1000 });
  return keyGetter;
}

export interface AppleClaims { sub: string; email: string | null; nonce: string | null }

export async function verifyAppleIdentityToken(token: string, audiences: string[]): Promise<AppleClaims> {
  const { payload } = await jwtVerify(token, keys(), { issuer: APPLE_ISSUER, audience: audiences, clockTolerance: 60 });
  if (typeof payload.sub !== "string" || !payload.sub) throw new Error("no subject");
  return {
    sub: payload.sub,
    email: typeof payload.email === "string" ? payload.email : null,
    nonce: typeof payload.nonce === "string" ? payload.nonce : null,
  };
}

/** A nonce for one sign-in: five minutes, single use. The web passes it raw; iOS passes its SHA-256. */
export async function mintNonce(db: D1Database): Promise<string> {
  const nonce = randomToken(24);
  await stmt(db, "INSERT INTO ceremonies (id, kind, user_id, challenge, payload_json, created_at, expires_at) VALUES (?,?,?,?,?,?,?)",
    uuid(), "apple", null, nonce, null, nowIso(), isoPlus(NONCE_TTL_SECONDS)).run();
  return nonce;
}

/** True when the token's nonce is the one we minted (raw or hashed) and it hasn't been used. */
export async function consumeNonce(db: D1Database, rawNonce: string, tokenNonce: string | null): Promise<boolean> {
  if (!tokenNonce || !rawNonce) return false;
  const row = await one<{ id: string; expires_at: string }>(db, "SELECT id, expires_at FROM ceremonies WHERE kind='apple' AND challenge=?", rawNonce);
  if (!row) return false;
  await stmt(db, "DELETE FROM ceremonies WHERE id=?", row.id).run();
  if (row.expires_at < nowIso()) return false;
  return tokenNonce === rawNonce || tokenNonce === (await sha256Hex(rawNonce));
}

export interface AppleHead { id: string; handle: string; first_show: string | null; disabled_at: string | null; created: boolean }

/** The head behind an Apple ID, made on first sign-in with a handle nobody has to think about. */
export async function findOrCreateAppleHead(db: D1Database, sub: string, givenName: string | null): Promise<AppleHead> {
  const existing = await one<{ id: string; handle: string; first_show: string | null; disabled_at: string | null }>(db,
    "SELECT u.id, u.handle, u.first_show, u.disabled_at FROM identities i JOIN users u ON u.id=i.user_id WHERE i.provider='apple' AND i.subject=?", sub);
  if (existing) return { ...existing, created: false };
  const handle = await freeHandle(db, givenName);
  const id = uuid();
  const now = nowIso();
  await db.batch([
    stmt(db, "INSERT INTO users (id, handle, node, name, first_show, role, share_spins, recovery_hash, recovery_rotated_at, created_at, updated_at) VALUES (?,?,?,?,NULL,'head',1,?,?,?,?)",
      id, handle, "BUS", handle.split("::")[1], await hashCode(generateRecoveryCode()), now, now, now),
    stmt(db, "INSERT INTO identities (provider, subject, user_id, created_at) VALUES ('apple', ?, ?, ?)", sub, id, now),
  ]);
  return { id, handle, first_show: null, disabled_at: null, created: true };
}

const LETTERS = "ABCDEFGHJKMNPQRSTVWXYZ";

/** BUS::WILL from a first name when it fits and is free; else BUS::<four letters>. */
export async function freeHandle(db: D1Database, givenName: string | null): Promise<string> {
  const base = (givenName ?? "").toUpperCase().replace(/[^A-Z0-9_]/g, "").slice(0, 12);
  const candidates: string[] = [];
  if (base.length >= 2) {
    candidates.push(`BUS::${base}`);
    for (let n = 2; n <= 9; n++) candidates.push(`BUS::${base.slice(0, 10)}${n}`);
  }
  for (let i = 0; i < 20; i++) {
    const bytes = new Uint8Array(4);
    crypto.getRandomValues(bytes);
    candidates.push("BUS::" + [...bytes].map((b) => LETTERS[b % LETTERS.length]).join(""));
  }
  for (const candidate of candidates) {
    const parsed = parseHandle(candidate);
    if ("error" in parsed) continue;
    const taken = await one(db, "SELECT 1 AS x FROM users WHERE handle=?", parsed.handle);
    if (!taken) return parsed.handle;
  }
  throw new Error("no free handle");
}

/** How the head's row says they came in. */
export async function identityProviders(db: D1Database, userId: string): Promise<string[]> {
  const rows = await db.prepare("SELECT provider FROM identities WHERE user_id=?").bind(userId).all<{ provider: string }>();
  return rows.results.map((r) => r.provider);
}
