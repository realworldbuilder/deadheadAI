/** One row per head in the lot; the same tape within twenty minutes updates in place. */
import type { Head } from "../env";
import { nowIso } from "../db/ids";
import { one, stmt } from "../db/notes";

export interface SpinBody { identifier?: string; showId?: string | null; trackTitle?: string; stopped?: boolean }

export async function recordSpin(db: D1Database, head: Head, body: SpinBody): Promise<void> {
  const now = nowIso();
  if (body.stopped) {
    await stmt(db, "DELETE FROM spins WHERE user_id=?", head.id).run();
    return;
  }
  if (!head.shareSpins || !body.identifier || !body.trackTitle) return;
  const last = await one<{ id: number; identifier: string; updated_at: string }>(db,
    "SELECT id, identifier, updated_at FROM spins WHERE user_id=? ORDER BY updated_at DESC LIMIT 1", head.id);
  const tenSecondsAgo = new Date(Date.now() - 10000).toISOString();
  if (last && last.updated_at > tenSecondsAgo) return;
  const twentyMinutesAgo = new Date(Date.now() - 20 * 60000).toISOString();
  if (last && last.identifier === body.identifier && last.updated_at > twentyMinutesAgo) {
    await stmt(db, "UPDATE spins SET track_title=?, updated_at=? WHERE id=?", body.trackTitle.slice(0, 120), now, last.id).run();
  } else {
    await db.batch([
      stmt(db, "DELETE FROM spins WHERE user_id=?", head.id),
      stmt(db, "INSERT INTO spins (user_id, handle, show_id, identifier, track_title, started_at, updated_at) VALUES (?,?,?,?,?,?,?)",
        head.id, head.handle, body.showId ?? null, body.identifier.slice(0, 200), body.trackTitle.slice(0, 120), now, now),
    ]);
  }
}
