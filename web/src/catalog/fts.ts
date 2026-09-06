/** Search over the catalog: FTS5 on the pre-expanded blob, or a LIKE scan as the fallback. */
import { q } from "../db/notes";
import type { CatalogShow } from "./queries";

const SHOW_COLS = "show_id,date,year,month,day,era_id,venue,city,state,setlist_status,recording_count,best_identifier,best_source_type,avg_rating,total_reviews,total_downloads,cover_image_url";

/** Port of CatalogDB.ftsQuery: each token quoted (5-8-77 stays one token, syntax can't inject) with prefix matching. */
export function ftsQuery(raw: string): string | null {
  const tokens = raw.split(/\s+/).map((t) => t.replace(/"/g, "")).filter(Boolean);
  if (tokens.length === 0) return null;
  return tokens.map((t) => `"${t}"*`).join(" ");
}

export async function search(db: D1Database, mode: string | undefined, raw: string, limit = 50): Promise<CatalogShow[]> {
  const tokens = raw.split(/\s+/).map((t) => t.replace(/"/g, "")).filter(Boolean);
  if (tokens.length === 0) return [];
  if (mode === "like") return searchLike(db, tokens, limit);
  try {
    return await searchFts(db, ftsQuery(raw)!, limit);
  } catch {
    return searchLike(db, tokens, limit);
  }
}

export function searchFts(db: D1Database, match: string, limit: number) {
  const cols = SHOW_COLS.split(",").map((c) => "s." + c).join(",");
  return q<CatalogShow>(db,
    `SELECT ${cols} FROM show_fts JOIN shows s ON s.rowid = show_fts.rowid WHERE show_fts MATCH ? ORDER BY rank LIMIT ?`,
    match, limit);
}

export function searchLike(db: D1Database, tokens: string[], limit: number) {
  const cols = SHOW_COLS.split(",").map((c) => "s." + c).join(",");
  const where = tokens.map(() => "b.blob LIKE ? ESCAPE '\\'").join(" AND ");
  const binds = tokens.map((t) => "%" + t.toLowerCase().replace(/[%_\\]/g, (ch) => "\\" + ch) + "%");
  return q<CatalogShow>(db,
    `SELECT ${cols} FROM web_search_blob b JOIN shows s ON s.rowid=b.rowid WHERE ${where} ORDER BY s.total_reviews DESC LIMIT ?`,
    ...binds, limit);
}
