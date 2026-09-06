/**
 * Shelves, mix tapes and the journal — the rows the iOS app will sync one
 * day, so ids are client-style UUIDs and every write bumps the owner's seq.
 */
import { nowIso, uuid } from "../db/ids";
import { one, q, stmt } from "../db/notes";
import * as cat from "../catalog/queries";
import { parseTracksJson, type Track } from "../archive/files";
import { normalizeSongKey } from "../catalog/setlist";
import { prettyDate } from "../fmt";

export async function nextSeq(db: D1Database, userId: string): Promise<number> {
  const row = await db.prepare("UPDATE users SET server_seq=server_seq+1, updated_at=? WHERE id=? RETURNING server_seq").bind(nowIso(), userId).first<{ server_seq: number }>();
  return row?.server_seq ?? 0;
}

export interface Shelf { id: string; user_id: string; name: string; blurb: string; is_private: number; created_at: string; updated_at: string }
export interface ShelfItem { id: string; shelf_id: string; show_identifier: string; show_id: string | null; show_date: string | null; display_name: string; sort_index: number; added_at: string }
export interface Mixtape { id: string; user_id: string; name: string; blurb: string; is_private: number; created_at: string; updated_at: string }
export interface MixtapeItem { id: string; mixtape_id: string; show_identifier: string; file_name: string; track_title: string; song_key: string; show_date_string: string; show_display_name: string; duration_seconds: number; sort_index: number; added_at: string }
export interface JournalEntry { id: string; show_identifier: string; show_id: string | null; show_date: string | null; show_display_name: string; body: string; mood: string | null; created_at: string; updated_at: string }

export function cleanName(raw: string, fallback: string): string {
  const name = raw.replace(/\s+/g, " ").trim().slice(0, 60);
  return name || fallback;
}

export function cleanBlurb(raw: string): string {
  return raw.replace(/\r\n?/g, "\n").trim().slice(0, 300);
}

// --- shelves ---------------------------------------------------------------

export function shelf(db: D1Database, id: string) {
  return one<Shelf>(db, "SELECT id, user_id, name, blurb, is_private, created_at, updated_at FROM shelves WHERE id=? AND deleted_at IS NULL", id);
}

export function shelfItems(db: D1Database, shelfId: string) {
  return q<ShelfItem>(db, "SELECT id, shelf_id, show_identifier, show_id, show_date, display_name, sort_index, added_at FROM shelf_items WHERE shelf_id=? AND deleted_at IS NULL ORDER BY sort_index, added_at", shelfId);
}

export async function createShelf(db: D1Database, userId: string, name: string, blurb = "", isPrivate = false): Promise<Shelf> {
  const id = uuid(), now = nowIso();
  const seq = await nextSeq(db, userId);
  await stmt(db, "INSERT INTO shelves (id, user_id, name, blurb, icon_name, is_private, created_at, updated_at, seq) VALUES (?,?,?,?,'sparkles',?,?,?,?)",
    id, userId, name, blurb, isPrivate ? 1 : 0, now, now, seq).run();
  return (await shelf(db, id))!;
}

export async function updateShelf(db: D1Database, userId: string, id: string, fields: { name: string; blurb: string; isPrivate: boolean }): Promise<void> {
  const seq = await nextSeq(db, userId);
  await db.batch([
    stmt(db, "UPDATE shelves SET name=?, blurb=?, is_private=?, updated_at=?, seq=? WHERE id=? AND user_id=?", fields.name, fields.blurb, fields.isPrivate ? 1 : 0, nowIso(), seq, id, userId),
    ...(fields.isPrivate ? [stmt(db, "UPDATE trees SET deleted_at=? WHERE kind='shelf' AND source_id=? AND deleted_at IS NULL", nowIso(), id)] : []),
  ]);
}

export async function deleteShelf(db: D1Database, userId: string, id: string): Promise<void> {
  const seq = await nextSeq(db, userId), now = nowIso();
  await db.batch([
    stmt(db, "UPDATE shelves SET deleted_at=?, updated_at=?, seq=? WHERE id=? AND user_id=?", now, now, seq, id, userId),
    stmt(db, "UPDATE shelf_items SET deleted_at=?, updated_at=?, seq=? WHERE shelf_id=? AND deleted_at IS NULL", now, now, seq, id),
    stmt(db, "UPDATE trees SET deleted_at=? WHERE kind='shelf' AND source_id=? AND deleted_at IS NULL", now, id),
  ]);
}

/** Put a night on a shelf: the best tape, the date, "5/8/77 Barton Hall". Idempotent per show. */
export async function shelveShow(db: D1Database, catalog: D1Database, userId: string, shelfId: string, showId: string): Promise<"added" | "already" | "noshow"> {
  const show = await cat.show(catalog, showId);
  if (!show || !show.best_identifier) return "noshow";
  const dup = await one(db, "SELECT 1 AS x FROM shelf_items WHERE shelf_id=? AND show_id=? AND deleted_at IS NULL", shelfId, showId);
  if (dup) return "already";
  const max = await one<{ m: number | null }>(db, "SELECT MAX(sort_index) AS m FROM shelf_items WHERE shelf_id=? AND deleted_at IS NULL", shelfId);
  const seq = await nextSeq(db, userId), now = nowIso();
  await db.batch([
    stmt(db, "INSERT INTO shelf_items (id, shelf_id, user_id, show_identifier, show_id, show_date, display_name, sort_index, added_at, updated_at, seq) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
      uuid(), shelfId, userId, show.best_identifier, show.show_id, show.date, `${prettyDate(show.date)} ${show.venue ?? ""}`.trim(), (max?.m ?? -1) + 1, now, now, seq),
    stmt(db, "UPDATE shelves SET updated_at=?, seq=? WHERE id=?", now, seq, shelfId),
  ]);
  return "added";
}

export async function removeShelfItem(db: D1Database, userId: string, shelfId: string, itemId: string): Promise<void> {
  const seq = await nextSeq(db, userId), now = nowIso();
  await db.batch([
    stmt(db, "UPDATE shelf_items SET deleted_at=?, updated_at=?, seq=? WHERE id=? AND shelf_id=? AND user_id=?", now, now, seq, itemId, shelfId, userId),
    stmt(db, "UPDATE shelves SET updated_at=?, seq=? WHERE id=?", now, seq, shelfId),
  ]);
}

/** Swap an item with its neighbour; sort indexes are renumbered densely on the way. */
export async function moveItem(db: D1Database, userId: string, table: "shelf_items" | "mixtape_items", parentCol: "shelf_id" | "mixtape_id", parentId: string, itemId: string, dir: "up" | "down"): Promise<void> {
  const rows = await q<{ id: string }>(db, `SELECT id FROM ${table} WHERE ${parentCol}=? AND deleted_at IS NULL ORDER BY sort_index, added_at`, parentId);
  const i = rows.findIndex((r) => r.id === itemId);
  if (i < 0) return;
  const j = dir === "up" ? i - 1 : i + 1;
  if (j < 0 || j >= rows.length) return;
  [rows[i], rows[j]] = [rows[j]!, rows[i]!];
  const seq = await nextSeq(db, userId), now = nowIso();
  await db.batch(rows.map((r, n) => stmt(db, `UPDATE ${table} SET sort_index=?, updated_at=?, seq=? WHERE id=? AND user_id=?`, n, now, seq, r.id, userId)));
}

// --- mix tapes -------------------------------------------------------------

export function mixtape(db: D1Database, id: string) {
  return one<Mixtape>(db, "SELECT id, user_id, name, blurb, is_private, created_at, updated_at FROM mixtapes WHERE id=? AND deleted_at IS NULL", id);
}

export function mixtapeItems(db: D1Database, id: string) {
  return q<MixtapeItem>(db, "SELECT id, mixtape_id, show_identifier, file_name, track_title, song_key, show_date_string, show_display_name, duration_seconds, sort_index, added_at FROM mixtape_items WHERE mixtape_id=? AND deleted_at IS NULL ORDER BY sort_index, added_at", id);
}

export async function createMixtape(db: D1Database, userId: string, name: string, blurb = "", isPrivate = false): Promise<Mixtape> {
  const id = uuid(), now = nowIso();
  const seq = await nextSeq(db, userId);
  await stmt(db, "INSERT INTO mixtapes (id, user_id, name, blurb, icon_name, is_private, created_at, updated_at, seq) VALUES (?,?,?,?,'music.note.list',?,?,?,?)",
    id, userId, name, blurb, isPrivate ? 1 : 0, now, now, seq).run();
  return (await mixtape(db, id))!;
}

export async function updateMixtape(db: D1Database, userId: string, id: string, fields: { name: string; blurb: string; isPrivate: boolean }): Promise<void> {
  const seq = await nextSeq(db, userId);
  await db.batch([
    stmt(db, "UPDATE mixtapes SET name=?, blurb=?, is_private=?, updated_at=?, seq=? WHERE id=? AND user_id=?", fields.name, fields.blurb, fields.isPrivate ? 1 : 0, nowIso(), seq, id, userId),
    ...(fields.isPrivate ? [stmt(db, "UPDATE trees SET deleted_at=? WHERE kind='mixtape' AND source_id=? AND deleted_at IS NULL", nowIso(), id)] : []),
  ]);
}

export async function deleteMixtape(db: D1Database, userId: string, id: string): Promise<void> {
  const seq = await nextSeq(db, userId), now = nowIso();
  await db.batch([
    stmt(db, "UPDATE mixtapes SET deleted_at=?, updated_at=?, seq=? WHERE id=? AND user_id=?", now, now, seq, id, userId),
    stmt(db, "UPDATE mixtape_items SET deleted_at=?, updated_at=?, seq=? WHERE mixtape_id=? AND deleted_at IS NULL", now, now, seq, id),
    stmt(db, "UPDATE trees SET deleted_at=? WHERE kind='mixtape' AND source_id=? AND deleted_at IS NULL", now, id),
  ]);
}

/** Resolve one file on a tape to the snapshot a mix tape row keeps, from the catalog's track list. */
export async function resolveTune(catalog: D1Database, identifier: string, fileName: string, liveTracks?: Track[] | null) {
  const rec = await cat.recording(catalog, identifier);
  const show = rec ? await cat.show(catalog, rec.show_id) : null;
  const tracks = liveTracks?.length ? liveTracks : parseTracksJson(await cat.tracksJson(catalog, identifier));
  const track = tracks.find((t) => t.fileName === fileName);
  if (!track) return null;
  return {
    identifier, fileName, title: track.title, seconds: track.seconds ?? 0, songKey: normalizeSongKey(track.title),
    dateString: show?.date ?? identifier.slice(2, 12), displayName: show ? `${prettyDate(show.date)} ${show.venue ?? ""}`.trim() : identifier,
  };
}

export async function addTune(db: D1Database, userId: string, mixtapeId: string, tune: NonNullable<Awaited<ReturnType<typeof resolveTune>>>): Promise<"added" | "already"> {
  const dup = await one(db, "SELECT 1 AS x FROM mixtape_items WHERE mixtape_id=? AND show_identifier=? AND file_name=? AND deleted_at IS NULL", mixtapeId, tune.identifier, tune.fileName);
  if (dup) return "already";
  const max = await one<{ m: number | null }>(db, "SELECT MAX(sort_index) AS m FROM mixtape_items WHERE mixtape_id=? AND deleted_at IS NULL", mixtapeId);
  const seq = await nextSeq(db, userId), now = nowIso();
  await db.batch([
    stmt(db, "INSERT INTO mixtape_items (id, mixtape_id, user_id, show_identifier, file_name, track_title, song_key, show_date_string, show_display_name, duration_seconds, sort_index, added_at, updated_at, seq) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
      uuid(), mixtapeId, userId, tune.identifier, tune.fileName, tune.title, tune.songKey, tune.dateString, tune.displayName, tune.seconds, (max?.m ?? -1) + 1, now, now, seq),
    stmt(db, "UPDATE mixtapes SET updated_at=?, seq=? WHERE id=?", now, seq, mixtapeId),
  ]);
  return "added";
}

export async function removeTune(db: D1Database, userId: string, mixtapeId: string, itemId: string): Promise<void> {
  const seq = await nextSeq(db, userId), now = nowIso();
  await db.batch([
    stmt(db, "UPDATE mixtape_items SET deleted_at=?, updated_at=?, seq=? WHERE id=? AND mixtape_id=? AND user_id=?", now, now, seq, itemId, mixtapeId, userId),
    stmt(db, "UPDATE mixtapes SET updated_at=?, seq=? WHERE id=?", now, seq, mixtapeId),
  ]);
}

// --- journal ---------------------------------------------------------------

export function journalEntries(db: D1Database, userId: string) {
  return q<JournalEntry>(db, "SELECT id, show_identifier, show_id, show_date, show_display_name, body, mood, created_at, updated_at FROM journal_entries WHERE user_id=? AND deleted_at IS NULL ORDER BY created_at DESC", userId);
}

export function journalEntry(db: D1Database, userId: string, id: string) {
  return one<JournalEntry>(db, "SELECT id, show_identifier, show_id, show_date, show_display_name, body, mood, created_at, updated_at FROM journal_entries WHERE id=? AND user_id=? AND deleted_at IS NULL", id, userId);
}

export async function writeJournal(db: D1Database, userId: string, show: cat.CatalogShow, body: string, mood: string | null): Promise<string> {
  const id = uuid(), now = nowIso();
  const seq = await nextSeq(db, userId);
  await stmt(db, "INSERT INTO journal_entries (id, user_id, show_identifier, show_id, show_date, show_display_name, body, mood, created_at, updated_at, seq) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
    id, userId, show.best_identifier ?? "", show.show_id, show.date, `${prettyDate(show.date)} ${show.venue ?? ""}`.trim(), body, mood, now, now, seq).run();
  return id;
}

export async function updateJournal(db: D1Database, userId: string, id: string, body: string, mood: string | null): Promise<void> {
  const seq = await nextSeq(db, userId);
  await stmt(db, "UPDATE journal_entries SET body=?, mood=?, updated_at=?, seq=? WHERE id=? AND user_id=?", body, mood, nowIso(), seq, id, userId).run();
}

export async function deleteJournal(db: D1Database, userId: string, id: string): Promise<void> {
  const seq = await nextSeq(db, userId), now = nowIso();
  await stmt(db, "UPDATE journal_entries SET deleted_at=?, updated_at=?, seq=? WHERE id=? AND user_id=?", now, now, seq, id, userId).run();
}
