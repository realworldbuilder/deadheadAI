/**
 * The phone's side of the notesfile. The app joins a head's account with a
 * short code from their page, gets a bearer token, and from then on keeps
 * shelves, mix tapes and the journal in step with the site, says what it's
 * spinning, and reads the notes under a show.
 */
import { Hono } from "hono";
import type { App, Head } from "../env";
import * as cat from "../catalog/queries";
import { consumeCeremony } from "../auth/webauthn";
import { bearerToken, createBearerSession, revokeBearer } from "../auth/sessions";
import { nowIso, uuid } from "../db/ids";
import { one, q, stmt } from "../db/notes";
import { recordSpin } from "../lot/spins";
import { nextSeq } from "../tapes/store";

export const api = new Hono<App>();

const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTVWXYZ23456789";
export const PAIR_TTL_SECONDS = 600;

export function pairCode(): string {
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  let out = "";
  for (const b of bytes) out += CODE_ALPHABET[b % CODE_ALPHABET.length];
  return out.slice(0, 3) + "-" + out.slice(3);
}

export function normalizeCode(raw: string): string {
  return raw.toUpperCase().replace(/[^A-Z0-9]/g, "").replace(/O/g, "0").replace(/[IL]/g, "1");
}

/** A code for the head's page: ten minutes, one use. */
export async function mintPairCode(db: D1Database, userId: string): Promise<string> {
  const code = pairCode();
  await db.batch([
    stmt(db, "DELETE FROM ceremonies WHERE kind='pair' AND user_id=?", userId),
    stmt(db, "INSERT INTO ceremonies (id, kind, user_id, challenge, payload_json, created_at, expires_at) VALUES (?,?,?,?,?,?,?)",
      uuid(), "pair", userId, normalizeCode(code), null, nowIso(), new Date(Date.now() + PAIR_TTL_SECONDS * 1000).toISOString()),
  ]);
  return code;
}

function requireBearer() {
  return async (c: any, next: any) => {
    if (!c.get("head") || !bearerToken(c)) return c.json({ error: "Not on the bus. Pair the phone from your page on the notesfile." }, 401);
    await next();
  };
}

// --- pairing ----------------------------------------------------------------

api.post("/api/pair", async (c) => {
  const body = await c.req.json<{ code?: string; device?: string }>().catch(() => null);
  const code = normalizeCode(String(body?.code ?? ""));
  if (code.length !== 6) return c.json({ error: "A code is six letters and digits, like ROSE-77." }, 400);
  const ceremony = await one<{ id: string; user_id: string; expires_at: string }>(c.env.NOTES,
    "SELECT id, user_id, expires_at FROM ceremonies WHERE kind='pair' AND challenge=?", code);
  if (!ceremony || ceremony.expires_at < nowIso()) return c.json({ error: "That code's no good. Codes last ten minutes; get a fresh one from your page." }, 400);
  await consumeCeremony(c.env.NOTES, ceremony.id, "pair");
  const head = await one<{ id: string; handle: string; first_show: string | null; disabled_at: string | null }>(c.env.NOTES,
    "SELECT id, handle, first_show, disabled_at FROM users WHERE id=?", ceremony.user_id);
  if (!head || head.disabled_at) return c.json({ error: "That handle's been frozen." }, 403);
  const token = await createBearerSession(c, head.id, `ios:${String(body?.device ?? "iPhone").slice(0, 60)}`);
  return c.json({ token, head: { id: head.id, handle: head.handle, firstShow: head.first_show } });
});

api.get("/api/me", requireBearer(), async (c) => {
  const head = c.get("head")!;
  const row = await one<{ first_show: string | null; server_seq: number }>(c.env.NOTES, "SELECT first_show, server_seq FROM users WHERE id=?", head.id);
  return c.json({ head: { id: head.id, handle: head.handle, firstShow: row?.first_show ?? null }, cursor: row?.server_seq ?? 0 });
});

api.post("/api/signout", requireBearer(), async (c) => {
  await revokeBearer(c);
  return c.body(null, 204);
});

// --- sync -------------------------------------------------------------------

interface ShelfRow { id: string; name: string; blurb: string; iconName: string; isPrivate: boolean; createdAt: string; updatedAt: string; deletedAt: string | null }
interface ShelfItemRow { id: string; shelfId: string; showIdentifier: string; showId: string | null; showDate: string | null; displayName: string; sortIndex: number; addedAt: string; updatedAt: string; deletedAt: string | null }
interface MixtapeRow { id: string; name: string; blurb: string; iconName: string; isPrivate: boolean; createdAt: string; updatedAt: string; deletedAt: string | null }
interface MixtapeItemRow { id: string; mixtapeId: string; showIdentifier: string; fileName: string; trackTitle: string; songKey: string; showDateString: string; showDisplayName: string; durationSeconds: number; sortIndex: number; addedAt: string; updatedAt: string; deletedAt: string | null }
interface JournalRow { id: string; showIdentifier: string; showId: string | null; showDate: string | null; showDisplayName: string; body: string; mood: string | null; createdAt: string; updatedAt: string; deletedAt: string | null }
export interface SyncBatch { shelves?: ShelfRow[]; shelfItems?: ShelfItemRow[]; mixtapes?: MixtapeRow[]; mixtapeItems?: MixtapeItemRow[]; journalEntries?: JournalRow[] }

api.get("/api/sync", requireBearer(), async (c) => {
  const head = c.get("head")!;
  const since = Number(c.req.query("since") ?? 0) || 0;
  const u = head.id;
  const [cursor, shelves, shelfItems, mixtapes, mixtapeItems, journalEntries] = await Promise.all([
    one<{ server_seq: number }>(c.env.NOTES, "SELECT server_seq FROM users WHERE id=?", u),
    q<any>(c.env.NOTES, "SELECT id, name, blurb, icon_name AS iconName, is_private AS isPrivate, created_at AS createdAt, updated_at AS updatedAt, deleted_at AS deletedAt FROM shelves WHERE user_id=? AND seq>? ORDER BY seq", u, since),
    q<any>(c.env.NOTES, "SELECT id, shelf_id AS shelfId, show_identifier AS showIdentifier, show_id AS showId, show_date AS showDate, display_name AS displayName, sort_index AS sortIndex, added_at AS addedAt, updated_at AS updatedAt, deleted_at AS deletedAt FROM shelf_items WHERE user_id=? AND seq>? ORDER BY seq", u, since),
    q<any>(c.env.NOTES, "SELECT id, name, blurb, icon_name AS iconName, is_private AS isPrivate, created_at AS createdAt, updated_at AS updatedAt, deleted_at AS deletedAt FROM mixtapes WHERE user_id=? AND seq>? ORDER BY seq", u, since),
    q<any>(c.env.NOTES, "SELECT id, mixtape_id AS mixtapeId, show_identifier AS showIdentifier, file_name AS fileName, track_title AS trackTitle, song_key AS songKey, show_date_string AS showDateString, show_display_name AS showDisplayName, duration_seconds AS durationSeconds, sort_index AS sortIndex, added_at AS addedAt, updated_at AS updatedAt, deleted_at AS deletedAt FROM mixtape_items WHERE user_id=? AND seq>? ORDER BY seq", u, since),
    q<any>(c.env.NOTES, "SELECT id, show_identifier AS showIdentifier, show_id AS showId, show_date AS showDate, show_display_name AS showDisplayName, body, mood, created_at AS createdAt, updated_at AS updatedAt, deleted_at AS deletedAt FROM journal_entries WHERE user_id=? AND seq>? ORDER BY seq", u, since),
  ]);
  const bool = (rows: any[]) => rows.map((r) => ({ ...r, isPrivate: r.isPrivate === 1 }));
  return c.json({ cursor: cursor?.server_seq ?? 0, shelves: bool(shelves), shelfItems, mixtapes: bool(mixtapes), mixtapeItems, journalEntries });
});

const UUID_RE = /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/;
const iso = (v: unknown, fallback: string) => (typeof v === "string" && !Number.isNaN(Date.parse(v)) ? new Date(v).toISOString() : fallback);
const text = (v: unknown, max: number, fallback = "") => (typeof v === "string" ? v.slice(0, max) : fallback);

api.post("/api/sync", requireBearer(), async (c) => {
  const head = c.get("head")!;
  const body = await c.req.json<SyncBatch>().catch(() => null);
  if (!body) return c.json({ error: "Malformed request." }, 400);
  const now = nowIso();
  const clamp = new Date(Date.now() + 5 * 60000).toISOString();
  const db = c.env.NOTES;
  const total = (body.shelves?.length ?? 0) + (body.shelfItems?.length ?? 0) + (body.mixtapes?.length ?? 0) + (body.mixtapeItems?.length ?? 0) + (body.journalEntries?.length ?? 0);
  if (total === 0) {
    const cur = await one<{ server_seq: number }>(db, "SELECT server_seq FROM users WHERE id=?", head.id);
    return c.json({ cursor: cur?.server_seq ?? 0, accepted: 0, skipped: 0 });
  }
  if (total > 500) return c.json({ error: "Five hundred rows a push. Send the rest next time." }, 413);
  const seq = await nextSeq(db, head.id);
  const upd = (v: unknown) => { const t = iso(v, now); return t > clamp ? clamp : t; };
  const del = (v: unknown) => (typeof v === "string" ? iso(v, now) : null);
  const statements: D1PreparedStatement[] = [];
  const shelfIds = new Set<string>();
  const mixIds = new Set<string>();

  for (const r of body.shelves ?? []) {
    if (!UUID_RE.test(r.id)) continue;
    shelfIds.add(r.id.toUpperCase());
    statements.push(stmt(db,
      `INSERT INTO shelves (id, user_id, name, blurb, icon_name, is_private, created_at, updated_at, deleted_at, seq) VALUES (?,?,?,?,?,?,?,?,?,?)
       ON CONFLICT(id) DO UPDATE SET name=excluded.name, blurb=excluded.blurb, icon_name=excluded.icon_name, is_private=excluded.is_private,
         updated_at=excluded.updated_at, deleted_at=excluded.deleted_at, seq=excluded.seq
       WHERE shelves.user_id=excluded.user_id AND excluded.updated_at > shelves.updated_at`,
      r.id.toUpperCase(), head.id, text(r.name, 60, "Shelf"), text(r.blurb, 300), text(r.iconName, 40, "sparkles"), r.isPrivate ? 1 : 0,
      iso(r.createdAt, now), upd(r.updatedAt), del(r.deletedAt), seq));
  }
  for (const r of body.mixtapes ?? []) {
    if (!UUID_RE.test(r.id)) continue;
    mixIds.add(r.id.toUpperCase());
    statements.push(stmt(db,
      `INSERT INTO mixtapes (id, user_id, name, blurb, icon_name, is_private, created_at, updated_at, deleted_at, seq) VALUES (?,?,?,?,?,?,?,?,?,?)
       ON CONFLICT(id) DO UPDATE SET name=excluded.name, blurb=excluded.blurb, icon_name=excluded.icon_name, is_private=excluded.is_private,
         updated_at=excluded.updated_at, deleted_at=excluded.deleted_at, seq=excluded.seq
       WHERE mixtapes.user_id=excluded.user_id AND excluded.updated_at > mixtapes.updated_at`,
      r.id.toUpperCase(), head.id, text(r.name, 60, "Mix Tape"), text(r.blurb, 300), text(r.iconName, 40, "music.note.list"), r.isPrivate ? 1 : 0,
      iso(r.createdAt, now), upd(r.updatedAt), del(r.deletedAt), seq));
  }
  // Parents an item needs must exist already or arrive in this push.
  const knownShelves = new Set((await q<{ id: string }>(db, "SELECT id FROM shelves WHERE user_id=?", head.id)).map((r) => r.id));
  const knownMixes = new Set((await q<{ id: string }>(db, "SELECT id FROM mixtapes WHERE user_id=?", head.id)).map((r) => r.id));
  const identifiers = [...new Set([...(body.shelfItems ?? []), ...(body.journalEntries ?? [])].map((r) => r.showIdentifier).filter(Boolean))];
  const showIdFor = new Map<string, string>();
  for (let i = 0; i < identifiers.length; i += 90) {
    const chunk = identifiers.slice(i, i + 90);
    const rows = await q<{ identifier: string; show_id: string }>(c.env.CATALOG, `SELECT identifier, show_id FROM recordings WHERE identifier IN (${chunk.map(() => "?").join(",")})`, ...chunk);
    for (const r of rows) showIdFor.set(r.identifier, r.show_id);
  }
  let skipped = 0;
  for (const r of body.shelfItems ?? []) {
    if (!UUID_RE.test(r.id) || !r.shelfId) { skipped++; continue; }
    const parent = r.shelfId.toUpperCase();
    if (!shelfIds.has(parent) && !knownShelves.has(parent)) { skipped++; continue; }
    statements.push(stmt(db,
      `INSERT INTO shelf_items (id, shelf_id, user_id, show_identifier, show_id, show_date, display_name, sort_index, added_at, updated_at, deleted_at, seq) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
       ON CONFLICT(id) DO UPDATE SET shelf_id=excluded.shelf_id, show_identifier=excluded.show_identifier, show_id=COALESCE(excluded.show_id, shelf_items.show_id), show_date=excluded.show_date,
         display_name=excluded.display_name, sort_index=excluded.sort_index, updated_at=excluded.updated_at, deleted_at=excluded.deleted_at, seq=excluded.seq
       WHERE shelf_items.user_id=excluded.user_id AND excluded.updated_at > shelf_items.updated_at`,
      r.id.toUpperCase(), parent, head.id, text(r.showIdentifier, 200), r.showId ?? showIdFor.get(r.showIdentifier) ?? null, r.showDate ? text(r.showDate, 10) : null,
      text(r.displayName, 120), Number(r.sortIndex) || 0, iso(r.addedAt, now), upd(r.updatedAt), del(r.deletedAt), seq));
  }
  for (const r of body.mixtapeItems ?? []) {
    if (!UUID_RE.test(r.id) || !r.mixtapeId) { skipped++; continue; }
    const parent = r.mixtapeId.toUpperCase();
    if (!mixIds.has(parent) && !knownMixes.has(parent)) { skipped++; continue; }
    statements.push(stmt(db,
      `INSERT INTO mixtape_items (id, mixtape_id, user_id, show_identifier, file_name, track_title, song_key, show_date_string, show_display_name, duration_seconds, sort_index, added_at, updated_at, deleted_at, seq) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
       ON CONFLICT(id) DO UPDATE SET mixtape_id=excluded.mixtape_id, sort_index=excluded.sort_index, track_title=excluded.track_title, song_key=excluded.song_key,
         show_date_string=excluded.show_date_string, show_display_name=excluded.show_display_name, duration_seconds=excluded.duration_seconds,
         updated_at=excluded.updated_at, deleted_at=excluded.deleted_at, seq=excluded.seq
       WHERE mixtape_items.user_id=excluded.user_id AND excluded.updated_at > mixtape_items.updated_at`,
      r.id.toUpperCase(), parent, head.id, text(r.showIdentifier, 200), text(r.fileName, 300), text(r.trackTitle, 200), text(r.songKey, 200),
      text(r.showDateString, 10), text(r.showDisplayName, 120), Number(r.durationSeconds) || 0, Number(r.sortIndex) || 0,
      iso(r.addedAt, now), upd(r.updatedAt), del(r.deletedAt), seq));
  }
  for (const r of body.journalEntries ?? []) {
    if (!UUID_RE.test(r.id)) { skipped++; continue; }
    statements.push(stmt(db,
      `INSERT INTO journal_entries (id, user_id, show_identifier, show_id, show_date, show_display_name, body, mood, created_at, updated_at, deleted_at, seq) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
       ON CONFLICT(id) DO UPDATE SET body=excluded.body, mood=excluded.mood, show_display_name=excluded.show_display_name, show_id=COALESCE(excluded.show_id, journal_entries.show_id),
         updated_at=excluded.updated_at, deleted_at=excluded.deleted_at, seq=excluded.seq
       WHERE journal_entries.user_id=excluded.user_id AND excluded.updated_at > journal_entries.updated_at`,
      r.id.toUpperCase(), head.id, text(r.showIdentifier, 200), r.showId ?? showIdFor.get(r.showIdentifier) ?? null, r.showDate ? text(r.showDate, 10) : null,
      text(r.showDisplayName, 120), text(r.body, 4000), r.mood ? text(r.mood, 30) : null, iso(r.createdAt, now), upd(r.updatedAt), del(r.deletedAt), seq));
  }
  let accepted = 0;
  for (let i = 0; i < statements.length; i += 50) {
    const results = await db.batch(statements.slice(i, i + 50));
    for (const r of results) accepted += r.meta?.changes ?? 0;
  }
  return c.json({ cursor: seq, accepted, skipped });
});

// --- the lot and the notes -------------------------------------------------

api.post("/api/spin", requireBearer(), async (c) => {
  const head = c.get("head")!;
  const body = await c.req.json<{ identifier?: string; showId?: string | null; trackTitle?: string; stopped?: boolean }>().catch(() => null);
  if (!body) return c.json({ error: "Malformed request." }, 400);
  await recordSpin(c.env.NOTES, head as Head, body);
  return c.body(null, 204);
});

/** The notes under a night, by date: every show on that date, newest first. Public. */
api.get("/api/notes/:date{\\d{4}-\\d{2}-\\d{2}}", async (c) => {
  const date = c.req.param("date");
  const shows = await cat.showsOnDate(c.env.CATALOG, date);
  const ids = shows.length ? shows.map((s) => s.show_id) : [date];
  const marks = ids.map(() => "?").join(",");
  const topics = await q<{ id: number; show_id: string; note_count: number }>(c.env.NOTES, `SELECT id, show_id, note_count FROM topics WHERE show_id IN (${marks})`, ...ids);
  if (topics.length === 0) return c.json({ noteCount: 0, notes: [], page: `/shows/${ids[0]}` });
  const tids = topics.map((t) => t.id);
  const rows = await q<{ topic_id: number; reply_no: number; handle: string | null; body: string; created_at: string; show_id: string }>(c.env.NOTES,
    `SELECT n.topic_id, n.reply_no, n.handle, n.body, n.created_at, t.show_id FROM notes n JOIN topics t ON t.id=n.topic_id
     WHERE n.topic_id IN (${tids.map(() => "?").join(",")}) AND n.deleted_at IS NULL ORDER BY n.id DESC LIMIT 50`, ...tids);
  c.header("cache-control", "public, max-age=60");
  return c.json({
    noteCount: topics.reduce((n, t) => n + t.note_count, 0),
    page: `/shows/${topics[0]!.show_id}`,
    notes: rows.map((r) => ({ ref: `${r.topic_id}.${r.reply_no}`, handle: r.handle, body: r.body, createdAt: r.created_at, showId: r.show_id, url: `/notes/${r.topic_id}.${r.reply_no}` })),
  });
});
