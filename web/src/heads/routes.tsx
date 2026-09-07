/** Heads: their page, their notes, their tape list as text. */
import { Hono } from "hono";
import type { App } from "../env";
import { parseHandle } from "../auth/handles";
import { one, q } from "../db/notes";
import { tapeListTxt } from "../fmt";
import { Frame, render } from "../views/frame";
import { NotFound } from "../views/errors";
import { HeadNotes, HeadPage, type HeadProfile, type MixtapeSummary, type ShelfSummary, type TreeSummary } from "../views/head";
import type { NoteRow } from "../views/notes";

export const heads = new Hono<App>();

const NOTE_COLS = "n.id, n.topic_id, n.reply_no, n.user_id, n.handle, n.body, n.created_at, n.edited_at, n.deleted_at, n.deleted_by, t.show_id, t.title";

async function profileFor(db: D1Database, raw: string): Promise<HeadProfile | null | "redirect"> {
  const parsed = parseHandle(raw, { allowReserved: true });
  if ("error" in parsed) return null;
  if (parsed.handle !== raw) return "redirect";
  return one<HeadProfile>(db, "SELECT id, handle, first_show, created_at FROM users WHERE handle=? AND disabled_at IS NULL", parsed.handle);
}

export function shelvesFor(db: D1Database, userId: string, includePrivate: boolean) {
  return q<ShelfSummary>(db,
    `SELECT s.id, s.name, s.blurb, s.is_private, (SELECT COUNT(*) FROM shelf_items i WHERE i.shelf_id=s.id AND i.deleted_at IS NULL) AS n
     FROM shelves s WHERE s.user_id=? AND s.deleted_at IS NULL ${includePrivate ? "" : "AND s.is_private=0"} ORDER BY s.created_at`, userId);
}

export function mixtapesFor(db: D1Database, userId: string, includePrivate: boolean) {
  return q<MixtapeSummary>(db,
    `SELECT m.id, m.name, m.blurb, m.is_private,
            (SELECT COUNT(*) FROM mixtape_items i WHERE i.mixtape_id=m.id AND i.deleted_at IS NULL) AS n,
            (SELECT COALESCE(SUM(duration_seconds),0) FROM mixtape_items i WHERE i.mixtape_id=m.id AND i.deleted_at IS NULL) AS seconds
     FROM mixtapes m WHERE m.user_id=? AND m.deleted_at IS NULL ${includePrivate ? "" : "AND m.is_private=0"} ORDER BY m.created_at`, userId);
}

export function treesFor(db: D1Database, userId: string) {
  return q<TreeSummary>(db,
    `SELECT t.id, t.kind,
            COALESCE((SELECT name FROM shelves WHERE id=t.source_id), (SELECT name FROM mixtapes WHERE id=t.source_id)) AS name,
            (SELECT handle FROM users WHERE id=t.owner_id) AS owner,
            (SELECT COUNT(*) FROM tree_members m WHERE m.tree_id=t.id) AS members
     FROM trees t WHERE t.deleted_at IS NULL AND (t.owner_id=? OR t.id IN (SELECT tree_id FROM tree_members WHERE user_id=?))
     ORDER BY t.created_at DESC`, userId, userId);
}

heads.get("/heads/:handle{[^/.]+\\.txt}", async (c) => {
  const raw = c.req.param("handle").replace(/\.txt$/, "");
  const profile = await profileFor(c.env.NOTES, raw.toUpperCase());
  if (!profile || profile === "redirect") return c.text("No head by that handle.\n", 404);
  const [shelves, mixtapes] = await Promise.all([shelvesFor(c.env.NOTES, profile.id, false), mixtapesFor(c.env.NOTES, profile.id, false)]);
  const shelfItems = await Promise.all(shelves.map((s) => q<{ show_date: string | null; display_name: string; show_identifier: string }>(c.env.NOTES,
    "SELECT show_date, display_name, show_identifier FROM shelf_items WHERE shelf_id=? AND deleted_at IS NULL ORDER BY sort_index", s.id)));
  const mixItems = await Promise.all(mixtapes.map((m) => q<{ show_date_string: string; track_title: string; duration_seconds: number; show_identifier: string; file_name: string }>(c.env.NOTES,
    "SELECT show_date_string, track_title, duration_seconds, show_identifier, file_name FROM mixtape_items WHERE mixtape_id=? AND deleted_at IS NULL ORDER BY sort_index", m.id)));
  const origin = new URL(c.req.url).origin;
  return c.text(tapeListTxt({
    handle: profile.handle, firstShow: profile.first_show, origin,
    shelves: shelves.map((s, i) => ({ name: s.name, items: shelfItems[i]! })),
    mixtapes: mixtapes.map((m, i) => ({ name: m.name, items: mixItems[i]! })),
  }));
});

heads.get("/heads/:handle{[^/.]+}", async (c) => {
  const raw = c.req.param("handle");
  const viewer = c.get("head");
  const profile = await profileFor(c.env.NOTES, raw);
  if (profile === "redirect") return c.redirect(`/heads/${raw.toUpperCase()}`, 301);
  if (!profile) return c.html(render(<Frame title="Nothing here" crumb={["Heads"]} head={viewer} page="none"><h1>No head by that handle.</h1><p>Try <a href="/notes">the notes</a> or <a href="/lot">the lot</a>.</p></Frame>), 404);
  const mine = viewer?.id === profile.id;
  const [noteCount, notes, shelves, mixtapes, trees, spinning] = await Promise.all([
    one<{ n: number }>(c.env.NOTES, "SELECT COUNT(*) AS n FROM notes WHERE user_id=? AND deleted_at IS NULL", profile.id),
    q<NoteRow>(c.env.NOTES, `SELECT ${NOTE_COLS} FROM notes n JOIN topics t ON t.id=n.topic_id WHERE n.user_id=? AND n.deleted_at IS NULL ORDER BY n.id DESC LIMIT 10`, profile.id),
    shelvesFor(c.env.NOTES, profile.id, mine),
    mixtapesFor(c.env.NOTES, profile.id, mine),
    treesFor(c.env.NOTES, profile.id),
    one<{ show_id: string | null; identifier: string; track_title: string }>(c.env.NOTES,
      "SELECT show_id, identifier, track_title FROM spins WHERE user_id=? AND updated_at > ? ORDER BY updated_at DESC LIMIT 1", profile.id, new Date(Date.now() - 20 * 60000).toISOString()),
  ]);
  return c.html(render(<Frame title={profile.handle} crumb={[profile.handle]} head={viewer} page={mine ? "me" : "none"}>
    <HeadPage profile={profile} viewer={viewer} noteCount={noteCount?.n ?? 0} notes={notes} shelves={shelves} mixtapes={mixtapes} trees={trees} spinning={spinning} />
  </Frame>));
});

heads.get("/heads/:handle{[^/.]+}/notes", async (c) => {
  const raw = c.req.param("handle");
  const viewer = c.get("head");
  const profile = await profileFor(c.env.NOTES, raw);
  if (profile === "redirect") return c.redirect(`/heads/${raw.toUpperCase()}/notes`, 301);
  if (!profile) return c.html(render(<Frame title="Nothing here" crumb={["Heads"]} head={viewer} page="none"><NotFound /></Frame>), 404);
  const before = Number(c.req.query("before") ?? 0) || null;
  const rows = before
    ? await q<NoteRow>(c.env.NOTES, `SELECT ${NOTE_COLS} FROM notes n JOIN topics t ON t.id=n.topic_id WHERE n.user_id=? AND n.deleted_at IS NULL AND n.id<? ORDER BY n.id DESC LIMIT 51`, profile.id, before)
    : await q<NoteRow>(c.env.NOTES, `SELECT ${NOTE_COLS} FROM notes n JOIN topics t ON t.id=n.topic_id WHERE n.user_id=? AND n.deleted_at IS NULL ORDER BY n.id DESC LIMIT 51`, profile.id);
  const page = rows.slice(0, 50);
  return c.html(render(<Frame title={`${profile.handle} · notes`} crumb={[profile.handle, "notes"]} head={viewer} page="none">
    <HeadNotes profile={profile} notes={page} older={rows.length > 50 ? page[page.length - 1]!.id : null} />
  </Frame>));
});
