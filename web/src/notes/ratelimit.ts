/** Thirty notes a day, twenty seconds apart. Enough for a head with a lot to say, not a script. */
import { one } from "../db/notes";

export const DAILY_NOTES = 30;
export const BURST_SECONDS = 20;

export async function checkNoteRate(db: D1Database, userId: string, now: Date = new Date()): Promise<"ok" | "daily" | "burst"> {
  const since = new Date(now.getTime() - 86400000).toISOString();
  const row = await one<{ n: number; last: string | null }>(db,
    "SELECT COUNT(*) AS n, MAX(created_at) AS last FROM notes WHERE user_id=? AND created_at > ?", userId, since);
  if (!row) return "ok";
  if (row.n >= DAILY_NOTES) return "daily";
  if (row.last && new Date(row.last).getTime() > now.getTime() - BURST_SECONDS * 1000) return "burst";
  return "ok";
}
