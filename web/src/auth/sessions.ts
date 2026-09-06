/** Sessions: an opaque token in an httpOnly cookie, its sha256 in D1. */
import type { Context, MiddlewareHandler } from "hono";
import { getCookie, setCookie, deleteCookie } from "hono/cookie";
import type { App, Head } from "../env";
import { isoPlus, nowIso, randomToken, sha256Hex } from "../db/ids";
import { one, stmt } from "../db/notes";

export const COOKIE = "nh_session";
const TTL_SECONDS = 90 * 86400;

interface SessionRow {
  expires_at: string; last_seen_at: string; id: string; handle: string; role: string;
  share_spins: number; first_show: string | null; notes_seen_through: number; disabled_at: string | null;
}

export function isAdmin(handle: string, role: string, adminHandles: string): boolean {
  if (role === "admin") return true;
  return adminHandles.split(",").map((h) => h.trim().toUpperCase()).filter(Boolean).includes(handle.toUpperCase());
}

/** The app sends its session as a bearer token instead of a cookie. */
export function bearerToken(c: Context<App>): string | null {
  const h = c.req.header("authorization") ?? "";
  return h.toLowerCase().startsWith("bearer ") ? h.slice(7).trim() || null : null;
}

export const sessionMiddleware: MiddlewareHandler<App> = async (c, next) => {
  c.set("head", null);
  const token = bearerToken(c) ?? getCookie(c, COOKIE, "host");
  if (token) {
    const hash = await sha256Hex(token);
    const row = await one<SessionRow>(c.env.NOTES,
      `SELECT s.expires_at, s.last_seen_at, u.id, u.handle, u.role, u.share_spins, u.first_show, u.notes_seen_through, u.disabled_at
       FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?`, hash);
    const now = nowIso();
    if (row && row.expires_at > now && !row.disabled_at) {
      c.set("head", {
        id: row.id, handle: row.handle, role: row.role, shareSpins: row.share_spins === 1,
        firstShow: row.first_show, notesSeenThrough: row.notes_seen_through,
        isAdmin: isAdmin(row.handle, row.role, c.env.ADMIN_HANDLES),
      });
      // Sliding expiry, written at most once a day so the write budget stays small.
      if (row.last_seen_at < isoPlus(-86400)) {
        c.executionCtx.waitUntil(
          stmt(c.env.NOTES, "UPDATE sessions SET last_seen_at=?, expires_at=? WHERE token_hash=?", now, isoPlus(TTL_SECONDS), hash).run());
      }
    }
  }
  await next();
};

export async function createSession(c: Context<App>, userId: string): Promise<void> {
  const token = randomToken(32);
  const hash = await sha256Hex(token);
  const now = nowIso();
  await stmt(c.env.NOTES,
    "INSERT INTO sessions (token_hash, user_id, created_at, last_seen_at, expires_at, user_agent) VALUES (?,?,?,?,?,?)",
    hash, userId, now, now, isoPlus(TTL_SECONDS), (c.req.header("user-agent") ?? "").slice(0, 200)).run();
  setCookie(c, COOKIE, token, { prefix: "host", httpOnly: true, secure: true, sameSite: "Lax", path: "/", maxAge: TTL_SECONDS });
}

/** A session for the app: the raw token goes back in the body, never a cookie. */
export async function createBearerSession(c: Context<App>, userId: string, device: string): Promise<string> {
  const token = randomToken(32);
  const hash = await sha256Hex(token);
  const now = nowIso();
  await stmt(c.env.NOTES,
    "INSERT INTO sessions (token_hash, user_id, created_at, last_seen_at, expires_at, user_agent) VALUES (?,?,?,?,?,?)",
    hash, userId, now, now, isoPlus(TTL_SECONDS), device.slice(0, 200)).run();
  return token;
}

export async function revokeBearer(c: Context<App>): Promise<void> {
  const token = bearerToken(c);
  if (!token) return;
  await stmt(c.env.NOTES, "DELETE FROM sessions WHERE token_hash=?", await sha256Hex(token)).run();
}

export async function revokeCurrent(c: Context<App>): Promise<void> {
  const token = getCookie(c, COOKIE, "host");
  if (token) {
    const hash = await sha256Hex(token);
    await stmt(c.env.NOTES, "DELETE FROM sessions WHERE token_hash=?", hash).run();
  }
  deleteCookie(c, COOKIE, { prefix: "host", path: "/", secure: true });
}

export async function revokeAll(c: Context<App>, userId: string, keepCurrent: boolean): Promise<void> {
  const token = getCookie(c, COOKIE, "host");
  const keep = keepCurrent && token ? await sha256Hex(token) : null;
  if (keep) await stmt(c.env.NOTES, "DELETE FROM sessions WHERE user_id=? AND token_hash<>?", userId, keep).run();
  else await stmt(c.env.NOTES, "DELETE FROM sessions WHERE user_id=?", userId).run();
  if (!keepCurrent) deleteCookie(c, COOKIE, { prefix: "host", path: "/", secure: true });
}

export function requireHead(): MiddlewareHandler<App> {
  return async (c, next) => {
    if (!c.get("head")) {
      const next_ = encodeURIComponent(c.req.path);
      return c.redirect(`/signin?next=${next_}`, 303);
    }
    await next();
  };
}

export function requireAdmin(): MiddlewareHandler<App> {
  return async (c, next) => {
    const head = c.get("head");
    if (!head || !head.isAdmin) return c.notFound();
    await next();
  };
}

export function currentHead(c: Context<App>): Head | null {
  return c.get("head");
}
