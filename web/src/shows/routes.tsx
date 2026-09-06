/** The catalog pages: front, shows, a night, a tape, years, on this day, search, songs. */
import { Hono } from "hono";
import type { App } from "../env";
import * as cat from "../catalog/queries";
import { search } from "../catalog/fts";
import { align, rows as tapeRows } from "../catalog/setlist";
import { parseTracksJson, type Track } from "../archive/files";
import { fetchTape } from "../archive/metadata";
import { q } from "../db/notes";
import { dayOfYear, firstSentence, parseHeadDate, prettyDate, showTitle, showTxt, todayMonthDay } from "../fmt";
import { eraForYear, notableFor, notableShow, quoteFor, runsOn } from "../kb";
import { Frame, render } from "../views/frame";
import { Home } from "../views/home";
import { ShowTopic, type NoteView } from "../views/show";
import { TapePage } from "../views/tape";
import { NotableIndex, OnThisDay, Search, Song, Songs, Year, Years } from "../views/lists";
import { NoShowThatNight, NotFound } from "../views/errors";
import { resolveRuns, withRunSegues } from "../catalog/runs";

export const shows = new Hono<App>();

const SHOW = ":id{\\d{4}-\\d{2}-\\d{2}(?:-early|-late)?}";

async function noteCounts(db: D1Database, ids: string[]): Promise<Map<string, number>> {
  const out = new Map<string, number>();
  for (let i = 0; i < ids.length; i += 90) {
    const chunk = ids.slice(i, i + 90);
    const marks = chunk.map(() => "?").join(",");
    const rows = await q<{ show_id: string; note_count: number }>(db,
      `SELECT show_id, note_count FROM topics WHERE show_id IN (${marks}) AND note_count > 0`, ...chunk);
    for (const r of rows) out.set(r.show_id, r.note_count);
  }
  return out;
}

shows.get("/", async (c) => {
  const head = c.get("head");
  const { month, day } = todayMonthDay();
  const doy = dayOfYear();
  const otd = await cat.showsOnMonthDay(c.env.CATALOG, month, day);
  let show: cat.CatalogShow | null = null;
  const withTape = otd.filter((s) => s.best_identifier);
  if (withTape.length) {
    // Rotate through the nights on this date, best-rated ones first.
    const ranked = [...withTape].sort((a, b) => (b.avg_rating ?? 0) - (a.avg_rating ?? 0));
    show = ranked[doy % Math.min(3, ranked.length)]!;
  } else {
    const n = notableFor(doy);
    show = (await cat.showsOnDate(c.env.CATALOG, n.date))[0] ?? null;
  }
  let tonight: Parameters<typeof Home>[0]["tonight"] = null;
  if (show) {
    const [tapes, digest, trackJson] = await Promise.all([
      cat.recordingsForShow(c.env.CATALOG, show.show_id),
      cat.digest(c.env.CATALOG, show.show_id),
      show.best_identifier ? cat.tracksJson(c.env.CATALOG, show.best_identifier) : Promise.resolve(null),
    ]);
    const best = tapes.find((t) => t.identifier === show!.best_identifier) ?? tapes[0] ?? null;
    const kb = notableShow(show.date);
    const blurb = kb?.blurb ?? (digest ? firstSentence(digest.consensus_summary) : null);
    const tracks = parseTracksJson(trackJson);
    tonight = { show, best, blurb, runs: best ? resolveRuns(runsOn(show.date), tracks) : [] };
  }
  const nearest = otd.length ? [] : await cat.nearestShows(c.env.CATALOG, `1977-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`, 1);
  const [notes, lot, counts, meta] = await Promise.all([
    q<NoteView & { show_id: string; title: string }>(c.env.NOTES,
      `SELECT (t.id || '.' || n.reply_no) AS ref, n.handle, n.body, n.created_at, n.deleted_by, t.show_id, t.title
       FROM notes n JOIN topics t ON t.id = n.topic_id WHERE n.deleted_at IS NULL ORDER BY n.id DESC LIMIT 8`),
    q<{ handle: string; show_id: string | null; identifier: string; track_title: string }>(c.env.NOTES,
      `SELECT handle, show_id, identifier, track_title FROM spins WHERE updated_at > ? ORDER BY updated_at DESC LIMIT 6`,
      new Date(Date.now() - 20 * 60000).toISOString()),
    q<{ notes: number; heads: number }>(c.env.NOTES,
      "SELECT (SELECT COUNT(*) FROM notes WHERE deleted_at IS NULL) AS notes, (SELECT COUNT(*) FROM users) AS heads"),
    cat.meta(c.env.CATALOG),
  ]);
  return c.html(render(
    <Frame title="RDVAX::GRATEFUL" crumb={["GRATEFUL"]} head={head} page="home">
      <Home
        head={head}
        tonight={tonight}
        otd={{ month, day, shows: otd, nearest }}
        notes={notes.map((n) => ({ ...n, body: n.body.length > 110 ? n.body.slice(0, 109).trimEnd() + "…" : n.body, show_label: n.title.split(" · ").slice(0, 2).join(" ") }))}
        lot={lot.map((s) => ({ ...s, date: s.show_id ? s.show_id.slice(0, 10) : null }))}
        counts={{ shows: Number(meta.show_count ?? 0).toLocaleString("en-US"), tapes: Number(meta.recording_count ?? 0).toLocaleString("en-US"), notes: counts[0]?.notes ?? 0, heads: counts[0]?.heads ?? 0 }}
        quote={quoteFor(doy)}
      />
    </Frame>));
});

shows.get("/shows", async (c) => {
  const { notableShows } = await import("../kb");
  const dates = [...new Set(notableShows.map((n) => n.date))];
  const found = await cat.showsByIds(c.env.CATALOG, dates);
  const byDate = new Map(found.map((s) => [s.date, s]));
  return c.html(render(<Frame title="Shows" crumb={["Shows"]} head={c.get("head")} page="shows"><NotableIndex byDate={byDate} /></Frame>));
});

shows.get("/shows/:id{\\d{4}-\\d{2}-\\d{2}(?:-early|-late)?\\.txt}", async (c) => {
  const id = c.req.param("id").replace(/\.txt$/, "");
  const show = await cat.show(c.env.CATALOG, id);
  if (!show) return c.text("No show that night.\n", 404);
  const [rawEntries, best, topic] = await Promise.all([
    cat.setlist(c.env.CATALOG, id),
    show.best_identifier ? cat.recording(c.env.CATALOG, show.best_identifier) : Promise.resolve(null),
    q<{ id: number }>(c.env.NOTES, "SELECT id FROM topics WHERE show_id=?", id),
  ]);
  const origin = new URL(c.req.url).origin;
  const entries = withRunSegues(rawEntries, runsOn(show.date));
  return c.text(showTxt({ show, entries, best, topicNumber: topic[0]?.id ?? null, origin }));
});

shows.get(`/shows/${SHOW}`, async (c) => {
  const id = c.req.param("id");
  const head = c.get("head");
  const show = await cat.show(c.env.CATALOG, id);
  if (!show) {
    const date = id.slice(0, 10);
    const siblings = await cat.showsOnDate(c.env.CATALOG, date);
    if (siblings.length === 1) return c.redirect(`/shows/${siblings[0]!.show_id}`, 302);
    const nearest = await cat.nearestShows(c.env.CATALOG, date);
    return c.html(render(<Frame title={prettyDate(date)} crumb={["GRATEFUL", prettyDate(date)]} head={head} page="shows"><NoShowThatNight date={date} nearest={nearest} /></Frame>), 404);
  }
  const ok = c.req.query("ok") === "shelved" ? "Shelved." : c.req.query("ok") === "already" ? "Already on that shelf." : null;
  return c.html(render(await topicPage(c, show, head, null, undefined, ok)));
});

export async function topicPage(c: any, show: cat.CatalogShow, head: any, error?: string | null, draft?: string, ok?: string | null) {
  const db = c.env.CATALOG as D1Database;
  const [rawEntries, tapes, digest, images, trackJson, aliases, [prev, next]] = await Promise.all([
    cat.setlist(db, show.show_id),
    cat.recordingsForShow(db, show.show_id),
    cat.digest(db, show.show_id),
    cat.images(db, show.date),
    show.best_identifier ? cat.tracksJson(db, show.best_identifier) : Promise.resolve(null),
    cat.aliases(db),
    cat.neighbours(db, show.show_id),
  ]);
  const entries = withRunSegues(rawEntries, runsOn(show.date));
  const best = tapes.find((t) => t.identifier === show.best_identifier) ?? tapes[0] ?? null;
  const bestTracks = parseTracksJson(trackJson);
  const matched = align(entries, bestTracks, aliases);
  const notesDb = c.env.NOTES as D1Database;
  const [topicRows, notes, shelves] = await Promise.all([
    q<{ id: number; note_count: number }>(notesDb, "SELECT id, note_count FROM topics WHERE show_id=?", show.show_id),
    q<NoteView>(notesDb,
      `SELECT (t.id || '.' || n.reply_no) AS ref, n.handle, n.body, n.created_at, n.deleted_by
       FROM notes n JOIN topics t ON t.id = n.topic_id WHERE t.show_id=? ORDER BY n.reply_no LIMIT 200`, show.show_id),
    head ? q<{ id: string; name: string }>(notesDb, "SELECT id, name FROM shelves WHERE user_id=? AND deleted_at IS NULL ORDER BY created_at", head.id) : Promise.resolve([]),
  ]);
  return (
    <Frame title={showTitle(show)} crumb={["GRATEFUL", prettyDate(show.date)]} head={head} page="shows">
      <ShowTopic
        show={show} entries={entries} matched={matched} tapes={tapes} best={best} bestTracks={bestTracks}
        digest={digest} images={images} topic={topicRows[0] ?? null} notes={notes}
        runs={best ? resolveRuns(runsOn(show.date), bestTracks) : []}
        head={head} shelves={shelves} prev={prev} next={next} error={error} draft={draft} ok={ok}
      />
    </Frame>
  );
}

shows.get(`/shows/${SHOW}/:identifier`, async (c) => {
  const id = c.req.param("id");
  const identifier = c.req.param("identifier");
  const head = c.get("head");
  const db = c.env.CATALOG;
  const tape = await cat.recording(db, identifier);
  const show = tape ? await cat.show(db, tape.show_id) : null;
  if (show && tape && show.show_id !== id && show.date === id.slice(0, 10)) return c.redirect(`/shows/${show.show_id}/${identifier}`, 302);
  if (!show || !tape || show.show_id !== id) {
    return c.html(render(<Frame title="Nothing here" crumb={["GRATEFUL"]} head={head} page="shows"><NotFound /></Frame>), 404);
  }
  const [rawEntries, others, trackJson, aliases] = await Promise.all([
    cat.setlist(db, id), cat.recordingsForShow(db, id), cat.tracksJson(db, identifier), cat.aliases(db),
  ]);
  const entries = withRunSegues(rawEntries, runsOn(show.date));
  let tracks: Track[] = parseTracksJson(trackJson);
  const fromCatalog = tracks.length > 0;
  const live = await fetchTape(identifier, c.executionCtx, { needTracks: !fromCatalog });
  if (!fromCatalog && live?.tracks) tracks = live.tracks;
  const reviews = live ? live.reviews : null;
  const mixtapes = head ? await q<{ id: string; name: string }>(c.env.NOTES, "SELECT id, name FROM mixtapes WHERE user_id=? AND deleted_at IS NULL ORDER BY created_at", head.id) : [];
  return c.html(render(
    <Frame title={`${showTitle(show)} · ${tape.source_type}`} crumb={["GRATEFUL", prettyDate(show.date), tape.source_type]} head={head} page="shows">
      <TapePage show={show} tape={tape} tracks={tracks} rows={tapeRows(entries, tracks, aliases)} fromCatalog={fromCatalog}
        reviews={reviews} others={others.filter((t) => t.identifier !== identifier)} head={head} mixtapes={mixtapes} />
    </Frame>));
});

shows.get("/years", async (c) => {
  const counts = await cat.yearCounts(c.env.CATALOG);
  return c.html(render(<Frame title="Years" crumb={["Years"]} head={c.get("head")} page="years"><Years counts={counts} /></Frame>));
});

shows.get("/years/:year{\\d{4}}", async (c) => {
  const year = Number(c.req.param("year"));
  const head = c.get("head");
  if (year < 1965 || year > 1995) return c.html(render(<Frame title="Nothing here" crumb={["Years"]} head={head} page="years"><NotFound /></Frame>), 404);
  const list = await cat.showsInYear(c.env.CATALOG, year);
  const notes = await noteCounts(c.env.NOTES, list.map((s) => s.show_id));
  const tapes = list.reduce((n, s) => n + s.recording_count, 0);
  return c.html(render(<Frame title={String(year)} crumb={["GRATEFUL", String(year)]} head={head} page="years"><Year year={year} shows={list} era={eraForYear(year)} notes={notes} tapes={tapes} /></Frame>));
});

shows.get("/on-this-day", async (c) => {
  const d = c.req.query("d");
  let { month, day } = todayMonthDay();
  const m = d ? /^(\d{2})-(\d{2})$/.exec(d) : null;
  if (m) { month = Number(m[1]); day = Number(m[2]); }
  const list = await cat.showsOnMonthDay(c.env.CATALOG, month, day);
  const nearest = list.length ? [] : await cat.nearestShows(c.env.CATALOG, `1977-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`, 1);
  const notes = await noteCounts(c.env.NOTES, list.map((s) => s.show_id));
  return c.html(render(<Frame title="On This Day" crumb={["On This Day"]} head={c.get("head")} page="otd"><OnThisDay month={month} day={day} shows={list} nearest={nearest} notes={notes} /></Frame>));
});

shows.get("/search", async (c) => {
  const raw = (c.req.query("q") ?? "").trim().slice(0, 120);
  const head = c.get("head");
  let list: cat.CatalogShow[] = [];
  let hit: Parameters<typeof Search>[0]["hit"] = null;
  if (raw) {
    list = await search(c.env.CATALOG, c.env.SEARCH_MODE, raw, 50);
    const iso = parseHeadDate(raw);
    if (iso && iso.length === 10) {
      const night = await cat.showsOnDate(c.env.CATALOG, iso);
      if (night.length) hit = { kind: "show", show: night[0]! };
      else hit = { kind: "noshow", date: iso, nearest: await cat.nearestShows(c.env.CATALOG, iso, 1) };
    } else {
      const key = await cat.canonicalKey(c.env.CATALOG, raw.toLowerCase().replace(/[^a-z' ]/g, " ").replace(/\s+/g, " ").trim());
      const song = await cat.songByKey(c.env.CATALOG, key);
      if (song) hit = { kind: "song", song };
    }
  }
  const notes = await noteCounts(c.env.NOTES, list.map((s) => s.show_id));
  return c.html(render(<Frame title={raw ? `“${raw}”` : "Search"} crumb={["Search"]} head={head} page="search"><Search q={raw} shows={list} hit={hit} notes={notes} /></Frame>));
});

shows.get("/songs", async (c) => {
  const qtext = (c.req.query("q") ?? "").trim().toLowerCase();
  let list = await cat.songs(c.env.CATALOG);
  if (qtext) list = list.filter((s) => s.title.toLowerCase().includes(qtext) || s.song_key.includes(qtext));
  return c.html(render(<Frame title="Songs" crumb={["Songs"]} head={c.get("head")} page="songs"><Songs songs={list} q={qtext} /></Frame>));
});

shows.get("/songs/:slug", async (c) => {
  const slug = c.req.param("slug").toLowerCase();
  const head = c.get("head");
  const song = await cat.songBySlug(c.env.CATALOG, slug);
  if (!song) return c.html(render(<Frame title="Nothing here" crumb={["Songs"]} head={head} page="songs"><h1>No tune by that name.</h1><p>Try <a href="/songs">the songs</a> or <a href="/search">Search</a>.</p></Frame>), 404);
  const [perf, into] = await Promise.all([cat.performances(c.env.CATALOG, song.song_key), cat.goesInto(c.env.CATALOG, song.song_key)]);
  return c.html(render(<Frame title={song.title} crumb={["Songs", song.title]} head={head} page="songs"><Song song={song} shows={perf} into={into} /></Frame>));
});
