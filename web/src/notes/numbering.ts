/** Topics are minted on the first note; replies are numbered per topic, densely and forever. */
import type { CatalogShow } from "../catalog/queries";
import { nowIso } from "../db/ids";
import { one, stmt } from "../db/notes";
import { showTitle } from "../fmt";

export interface TopicRow { id: number; show_id: string; title: string; note_count: number; last_note_at: string | null }

export async function topicFor(db: D1Database, showId: string): Promise<TopicRow | null> {
  return one<TopicRow>(db, "SELECT id, show_id, title, note_count, last_note_at FROM topics WHERE show_id=?", showId);
}

export async function topicById(db: D1Database, id: number): Promise<TopicRow | null> {
  return one<TopicRow>(db, "SELECT id, show_id, title, note_count, last_note_at FROM topics WHERE id=?", id);
}

/** The topic for a show, minted if this is its first note. */
export async function ensureTopic(db: D1Database, show: CatalogShow): Promise<TopicRow> {
  const existing = await topicFor(db, show.show_id);
  if (existing) return existing;
  await stmt(db, "INSERT OR IGNORE INTO topics (show_id, title, note_count, created_at) VALUES (?,?,0,?)", show.show_id, showTitle(show), nowIso()).run();
  return (await topicFor(db, show.show_id))!;
}

export interface MintedNote { id: number; reply_no: number }

/** One atomic statement mints the next reply number, so two heads posting at once never collide. */
export async function mintReply(db: D1Database, topicId: number, userId: string, handle: string, body: string): Promise<MintedNote> {
  const now = nowIso();
  const row = await db.prepare(
    `INSERT INTO notes (topic_id, reply_no, user_id, handle, body, created_at)
     SELECT ?, COALESCE(MAX(reply_no), 0) + 1, ?, ?, ?, ? FROM notes WHERE topic_id=?
     RETURNING id, reply_no`).bind(topicId, userId, handle, body, now, topicId).first<MintedNote>();
  if (!row) throw new Error("note not minted");
  await stmt(db, "UPDATE topics SET note_count=note_count+1, last_note_at=? WHERE id=?", now, topicId).run();
  return row;
}

/** Note bodies: trimmed, Unix newlines, 1 to 4,000 characters. Plain text; JSX escapes it on the way out. */
export function cleanBody(raw: string): { body: string } | { error: string } {
  const body = raw.replace(/\r\n?/g, "\n").replace(/[ \t]+$/gm, "").trim();
  if (!body) return { error: "Nothing in the note." };
  if (body.length > 4000) return { error: `That's ${body.length} characters. Notes stop at 4,000 — split it into two.` };
  return { body };
}
