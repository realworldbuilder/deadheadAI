/**
 * Passkeys. Thin wrappers over @simplewebauthn/server so the ceremony
 * storage and the RP ID rules live in one place. Every ceremony is a row
 * with a five-minute life, consumed on first use.
 */
import {
  generateAuthenticationOptions, generateRegistrationOptions,
  verifyAuthenticationResponse, verifyRegistrationResponse,
  type AuthenticationResponseJSON, type RegistrationResponseJSON,
} from "@simplewebauthn/server";
import type { Context } from "hono";
import type { App } from "../env";
import { fromBase64url, isoPlus, nowIso, randomToken } from "../db/ids";
import { one, q, stmt } from "../db/notes";

export const CEREMONY_TTL = 300;

export type CeremonyKind = "signup" | "signin" | "add_passkey" | "recovery";

export interface Ceremony { id: string; kind: string; user_id: string | null; challenge: string; payload_json: string | null; expires_at: string }

export function rpId(c: Context<App>): string {
  return c.env.RP_ID_OVERRIDE || new URL(c.req.url).hostname;
}

export function origin(c: Context<App>): string {
  return new URL(c.req.url).origin;
}

export async function beginCeremony(db: D1Database, kind: CeremonyKind, userId: string | null, challenge: string, payload: unknown): Promise<string> {
  const id = randomToken(16);
  await stmt(db, "INSERT INTO ceremonies (id, kind, user_id, challenge, payload_json, created_at, expires_at) VALUES (?,?,?,?,?,?,?)",
    id, kind, userId, challenge, payload == null ? null : JSON.stringify(payload), nowIso(), isoPlus(CEREMONY_TTL)).run();
  return id;
}

/** Fetch and delete in one go, so a ceremony can never be replayed. */
export async function consumeCeremony(db: D1Database, id: string, kind: CeremonyKind): Promise<Ceremony | null> {
  const row = await one<Ceremony>(db, "SELECT id, kind, user_id, challenge, payload_json, expires_at FROM ceremonies WHERE id=?", id);
  if (!row) return null;
  await stmt(db, "DELETE FROM ceremonies WHERE id=?", id).run();
  if (row.kind !== kind || row.expires_at < nowIso()) return null;
  return row;
}

export interface PasskeyRow {
  id: string; user_id: string; public_key: ArrayBuffer | Uint8Array; counter: number; transports: string | null;
  device_type: string | null; backed_up: number; label: string | null; created_at: string; last_used_at: string | null;
}

export function passkeysFor(db: D1Database, userId: string) {
  return q<PasskeyRow>(db, "SELECT id, user_id, public_key, counter, transports, device_type, backed_up, label, created_at, last_used_at FROM passkeys WHERE user_id=? ORDER BY created_at", userId);
}

export async function registrationOptions(c: Context<App>, opts: { userId: string; handle: string; exclude: PasskeyRow[] }) {
  return generateRegistrationOptions({
    rpName: c.env.RP_NAME || "Nethead",
    rpID: rpId(c),
    userName: opts.handle,
    userDisplayName: opts.handle,
    userID: new TextEncoder().encode(opts.userId) as Uint8Array<ArrayBuffer>,
    attestationType: "none",
    authenticatorSelection: { residentKey: "preferred", userVerification: "preferred" },
    supportedAlgorithmIDs: [-7, -257],
    excludeCredentials: opts.exclude.map((p) => ({ id: p.id, transports: p.transports ? JSON.parse(p.transports) : undefined })),
  });
}

export async function verifyRegistration(c: Context<App>, response: RegistrationResponseJSON, challenge: string) {
  const result = await verifyRegistrationResponse({
    response, expectedChallenge: challenge, expectedOrigin: origin(c), expectedRPID: rpId(c),
    requireUserVerification: false, supportedAlgorithmIDs: [-7, -257],
  });
  if (!result.verified || !result.registrationInfo) return null;
  const info = result.registrationInfo;
  return {
    id: info.credential.id,
    publicKey: info.credential.publicKey,
    counter: info.credential.counter,
    transports: info.credential.transports ?? response.response.transports ?? [],
    deviceType: info.credentialDeviceType,
    backedUp: info.credentialBackedUp,
  };
}

export async function authenticationOptions(c: Context<App>, allow: PasskeyRow[]) {
  return generateAuthenticationOptions({
    rpID: rpId(c),
    userVerification: "preferred",
    allowCredentials: allow.map((p) => ({ id: p.id, transports: p.transports ? JSON.parse(p.transports) : undefined })),
  });
}

export async function verifyAuthentication(c: Context<App>, response: AuthenticationResponseJSON, challenge: string, passkey: PasskeyRow) {
  const key = (passkey.public_key instanceof Uint8Array ? passkey.public_key : new Uint8Array(passkey.public_key)) as Uint8Array<ArrayBuffer>;
  const result = await verifyAuthenticationResponse({
    response, expectedChallenge: challenge, expectedOrigin: origin(c), expectedRPID: rpId(c),
    credential: { id: passkey.id, publicKey: key, counter: passkey.counter, transports: passkey.transports ? JSON.parse(passkey.transports) : undefined },
    requireUserVerification: false,
  });
  if (!result.verified) return null;
  return result.authenticationInfo;
}

/** "iPhone", "Mac", "Windows", "Android", "security key" — a label to tell passkeys apart. */
export function labelFor(userAgent: string, attachment: string | undefined): string {
  if (attachment === "cross-platform") return "security key";
  const ua = userAgent.toLowerCase();
  if (ua.includes("iphone")) return "iPhone";
  if (ua.includes("ipad")) return "iPad";
  if (ua.includes("android")) return "Android";
  if (ua.includes("mac os") || ua.includes("macintosh")) return "Mac";
  if (ua.includes("windows")) return "Windows";
  if (ua.includes("linux")) return "Linux";
  return "passkey";
}

export { fromBase64url };
