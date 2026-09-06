/** Reads over the catalog database, named after CatalogDB.swift's calls. */
import { one, q } from "../db/notes";

export interface CatalogShow {
  show_id: string; date: string; year: number; month: number; day: number;
  era_id: string | null; venue: string | null; city: string | null; state: string | null;
  setlist_status: string; recording_count: number; best_identifier: string | null;
  best_source_type: string | null; avg_rating: number | null; total_reviews: number;
  total_downloads: number; cover_image_url: string | null;
}
export interface CatalogRecording {
  identifier: string; show_id: string; title: string | null; source_type: string;
  source_text: string | null; lineage: string | null; taper: string | null;
  avg_rating: number | null; num_reviews: number; downloads: number; quality_score: number;
}
export interface SetlistEntry {
  show_id: string; position: number; set_label: string; song_key: string; song_title: string; segues_into_next: number;
}
export interface CatalogSong { song_key: string; title: string; times_played: number; first_played: string | null; last_played: string | null }
export interface Digest {
  show_id: string; consensus_summary: string; standout_songs_json: string; sentiment: string;
  derived_rating: number; rating_rationale: string; model: string; generated_at: string;
}
export interface ShowImage { date: string; position: number; kind: string; url: string; width: number | null; height: number | null }
export interface YearCount { year: number; show_count: number; recording_count: number; first_date: string; last_date: string }

const SHOW_COLS = "show_id,date,year,month,day,era_id,venue,city,state,setlist_status,recording_count,best_identifier,best_source_type,avg_rating,total_reviews,total_downloads,cover_image_url";
const REC_COLS = "identifier,show_id,title,source_type,source_text,lineage,taper,avg_rating,num_reviews,downloads,quality_score";

export const SHOW_ID = /^\d{4}-\d{2}-\d{2}(?:-early|-late)?$/;

export function show(db: D1Database, showId: string) {
  return one<CatalogShow>(db, `SELECT ${SHOW_COLS} FROM shows WHERE show_id=?`, showId);
}

export function showsOnDate(db: D1Database, date: string) {
  return q<CatalogShow>(db, `SELECT ${SHOW_COLS} FROM shows WHERE date=? ORDER BY show_id`, date);
}

export function showsByIds(db: D1Database, ids: string[]) {
  if (ids.length === 0) return Promise.resolve([] as CatalogShow[]);
  const marks = ids.map(() => "?").join(",");
  return q<CatalogShow>(db, `SELECT ${SHOW_COLS} FROM shows WHERE show_id IN (${marks})`, ...ids);
}

export function showsInYear(db: D1Database, year: number) {
  return q<CatalogShow>(db, `SELECT ${SHOW_COLS} FROM shows WHERE year=? ORDER BY date, show_id`, year);
}

export function showsOnMonthDay(db: D1Database, month: number, day: number) {
  return q<CatalogShow>(db, `SELECT ${SHOW_COLS} FROM shows WHERE month=? AND day=? ORDER BY year, show_id`, month, day);
}

/** The nights nearest a date the band didn't play, two either side. */
export async function nearestShows(db: D1Database, date: string, each = 2) {
  const before = await q<CatalogShow>(db, `SELECT ${SHOW_COLS} FROM shows WHERE date<? ORDER BY date DESC LIMIT ?`, date, each);
  const after = await q<CatalogShow>(db, `SELECT ${SHOW_COLS} FROM shows WHERE date>? ORDER BY date ASC LIMIT ?`, date, each);
  return [...before.reverse(), ...after];
}

export function neighbours(db: D1Database, showId: string) {
  return Promise.all([
    one<CatalogShow>(db, `SELECT ${SHOW_COLS} FROM shows WHERE show_id<? ORDER BY show_id DESC LIMIT 1`, showId),
    one<CatalogShow>(db, `SELECT ${SHOW_COLS} FROM shows WHERE show_id>? ORDER BY show_id ASC LIMIT 1`, showId),
  ]);
}

export function topRated(db: D1Database, limit: number, from?: number, to?: number) {
  if (from != null && to != null) {
    return q<CatalogShow>(db,
      `SELECT ${SHOW_COLS} FROM shows WHERE total_reviews>=5 AND year BETWEEN ? AND ? ORDER BY avg_rating DESC, total_reviews DESC LIMIT ?`,
      from, to, limit);
  }
  return q<CatalogShow>(db,
    `SELECT ${SHOW_COLS} FROM shows WHERE total_reviews>=5 ORDER BY avg_rating DESC, total_reviews DESC LIMIT ?`, limit);
}

export function yearCounts(db: D1Database) {
  return q<YearCount>(db, "SELECT year,show_count,recording_count,first_date,last_date FROM web_year_counts ORDER BY year");
}

export function setlist(db: D1Database, showId: string) {
  return q<SetlistEntry>(db,
    "SELECT show_id,position,set_label,song_key,song_title,segues_into_next FROM setlist_entries WHERE show_id=? ORDER BY position", showId);
}

export function recordingsForShow(db: D1Database, showId: string) {
  return q<CatalogRecording>(db,
    `SELECT ${REC_COLS} FROM recordings WHERE show_id=? ORDER BY quality_score DESC, identifier`, showId);
}

export function recording(db: D1Database, identifier: string) {
  return one<CatalogRecording>(db, `SELECT ${REC_COLS} FROM recordings WHERE identifier=?`, identifier);
}

export async function tracksJson(db: D1Database, identifier: string): Promise<string | null> {
  const row = await one<{ tracks_json: string }>(db, "SELECT tracks_json FROM recording_tracks WHERE identifier=?", identifier);
  return row?.tracks_json ?? null;
}

export function digest(db: D1Database, showId: string) {
  return one<Digest>(db,
    "SELECT show_id,consensus_summary,standout_songs_json,sentiment,derived_rating,rating_rationale,model,generated_at FROM ai_digest WHERE show_id=?", showId);
}

export function images(db: D1Database, date: string) {
  return q<ShowImage>(db, "SELECT date,position,kind,url,width,height FROM show_images WHERE date=? ORDER BY position", date);
}

export function songByKey(db: D1Database, key: string) {
  return one<CatalogSong>(db, "SELECT song_key,title,times_played,first_played,last_played FROM songs WHERE song_key=?", key);
}

export async function songBySlug(db: D1Database, slug: string) {
  const row = await one<{ song_key: string }>(db, "SELECT song_key FROM web_song_slugs WHERE slug=?", slug);
  const key = row?.song_key ?? slug.replace(/-/g, " ");
  return songByKey(db, key);
}

export function songs(db: D1Database, limit = 600) {
  return q<CatalogSong>(db, "SELECT song_key,title,times_played,first_played,last_played FROM songs ORDER BY times_played DESC, title LIMIT ?", limit);
}

export async function canonicalKey(db: D1Database, key: string): Promise<string> {
  const row = await one<{ canonical_key: string }>(db, "SELECT canonical_key FROM song_aliases WHERE variant_key=?", key);
  return row?.canonical_key ?? key;
}

export async function aliases(db: D1Database): Promise<Record<string, string>> {
  const rows = await q<{ variant_key: string; canonical_key: string }>(db, "SELECT variant_key, canonical_key FROM song_aliases");
  const out: Record<string, string> = {};
  for (const r of rows) out[r.variant_key] = r.canonical_key;
  return out;
}

/** Every night a song was played, with its neighbours' keys for "goes into". */
export function performances(db: D1Database, key: string) {
  return q<CatalogShow & { position: number; segues_into_next: number }>(db,
    `SELECT ${SHOW_COLS.split(",").map((c) => "s." + c).join(",")}, e.position, e.segues_into_next
     FROM setlist_entries e JOIN shows s ON s.show_id=e.show_id
     WHERE e.song_key=? ORDER BY s.date, s.show_id, e.position`, key);
}

/** What the song went into, counted across the catalog. */
export function goesInto(db: D1Database, key: string, limit = 12) {
  return q<{ song_key: string; song_title: string; n: number }>(db,
    `SELECT n.song_key, MAX(n.song_title) AS song_title, COUNT(*) AS n
     FROM setlist_entries e JOIN setlist_entries n ON n.show_id=e.show_id AND n.position=e.position+1
     WHERE e.song_key=? AND e.segues_into_next=1 GROUP BY n.song_key ORDER BY n DESC LIMIT ?`, key, limit);
}

export async function meta(db: D1Database): Promise<Record<string, string>> {
  const rows = await q<{ key: string; value: string }>(db, "SELECT key, value FROM web_meta");
  const out: Record<string, string> = {};
  for (const r of rows) out[r.key] = r.value;
  return out;
}

/** Venues with the most nights. */
export function venues(db: D1Database, limit = 40) {
  return q<{ venue: string; city: string | null; state: string | null; n: number; first: string; last: string }>(db,
    `SELECT venue, MAX(city) AS city, MAX(state) AS state, COUNT(*) AS n, MIN(date) AS first, MAX(date) AS last
     FROM shows WHERE venue IS NOT NULL GROUP BY venue ORDER BY n DESC LIMIT ?`, limit);
}
