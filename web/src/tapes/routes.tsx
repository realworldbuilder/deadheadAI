/** Shelves, mix tapes and the journal: your edit pages, everyone's read pages, the index. */
import { Hono } from "hono";
import type { App } from "../env";
import * as cat from "../catalog/queries";
import { requireHead } from "../auth/sessions";
import { one, q } from "../db/notes";
import { parseHeadDate, prettyDate } from "../fmt";
import { fetchTape } from "../archive/metadata";
import { Frame, render } from "../views/frame";
import { NotFound } from "../views/errors";
import { Confirm, MeJournal, MeJournalEntry, MeMixtape, MeMixtapes, MeShelf, MeShelves, MixtapePage, ShelfPage, TapeLists, type TreeState } from "../views/tapes";
import * as store from "./store";
import { cleanBody } from "../notes/numbering";

export const tapes = new Hono<App>();

async function treeFor(db: D1Database, kind: "shelf" | "mixtape", sourceId: string, viewerId: string | null): Promise<TreeState | null> {
  const row = await one<{ id: string; owner: string; members: number; joined: number }>(db,
    `SELECT t.id, (SELECT handle FROM users WHERE id=t.owner_id) AS owner,
            (SELECT COUNT(*) FROM tree_members m WHERE m.tree_id=t.id) AS members,
            (SELECT COUNT(*) FROM tree_members m WHERE m.tree_id=t.id AND m.user_id=?) AS joined
     FROM trees t WHERE t.kind=? AND t.source_id=? AND t.deleted_at IS NULL`, viewerId ?? "", kind, sourceId);
  return row ? { id: row.id, owner: row.owner, members: row.members, joined: row.joined > 0 } : null;
}

function notFound(c: any) {
  return c.html(render(<Frame title="Nothing here" crumb={["GRATEFUL"]} head={c.get("head")} page="none"><NotFound /></Frame>), 404);
}

// --- shelves ---------------------------------------------------------------

tapes.get("/me/shelves", requireHead(), async (c) => {
  const head = c.get("head")!;
  const shelves = await q<store.Shelf & { n: number }>(c.env.NOTES,
    "SELECT s.id, s.user_id, s.name, s.blurb, s.is_private, s.created_at, s.updated_at, (SELECT COUNT(*) FROM shelf_items i WHERE i.shelf_id=s.id AND i.deleted_at IS NULL) AS n FROM shelves s WHERE s.user_id=? AND s.deleted_at IS NULL ORDER BY s.created_at", head.id);
  const ok = c.req.query("ok") === "shelved" ? "Shelved." : c.req.query("ok") === "tossed" ? "Tossed." : null;
  return c.html(render(<Frame title="Shelves" crumb={[head.handle, "shelves"]} head={head} page="me"><MeShelves head={head} shelves={shelves} ok={ok} error={c.req.query("error")} show={c.req.query("show")} /></Frame>));
});

tapes.post("/me/shelves", requireHead(), async (c) => {
  const head = c.get("head")!;
  const form = await c.req.parseBody();
  const shelf = await store.createShelf(c.env.NOTES, head.id, store.cleanName(String(form.name ?? ""), "New Shelf"));
  const showId = String(form.show_id ?? "");
  if (showId) {
    const r = await store.shelveShow(c.env.NOTES, c.env.CATALOG, head.id, shelf.id, showId);
    if (r === "added") return c.redirect(`/shows/${showId}?ok=shelved`, 303);
  }
  return c.redirect(`/me/shelves/${shelf.id}`, 303);
});

/** "Shelve it" from a topic page. */
tapes.post("/me/shelves/add", requireHead(), async (c) => {
  const head = c.get("head")!;
  const form = await c.req.parseBody();
  const showId = String(form.show_id ?? "");
  const shelfId = String(form.shelf_id ?? "");
  if (!cat.SHOW_ID.test(showId)) return notFound(c);
  if (shelfId === "new" || !shelfId) return c.redirect(`/me/shelves?show=${showId}`, 303);
  const shelf = await store.shelf(c.env.NOTES, shelfId);
  if (!shelf || shelf.user_id !== head.id) return notFound(c);
  const r = await store.shelveShow(c.env.NOTES, c.env.CATALOG, head.id, shelf.id, showId);
  return c.redirect(`/shows/${showId}?ok=${r === "already" ? "already" : "shelved"}`, 303);
});

tapes.get("/me/shelves/:id", requireHead(), async (c) => {
  const head = c.get("head")!;
  const shelf = await store.shelf(c.env.NOTES, c.req.param("id"));
  if (!shelf || shelf.user_id !== head.id) return notFound(c);
  const [items, tree] = await Promise.all([store.shelfItems(c.env.NOTES, shelf.id), treeFor(c.env.NOTES, "shelf", shelf.id, head.id)]);
  return c.html(render(<Frame title={shelf.name} crumb={[head.handle, "shelves", shelf.name]} head={head} page="me"><MeShelf head={head} shelf={shelf} items={items} tree={tree} ok={c.req.query("ok") === "1" ? "Saved." : null} /></Frame>));
});

tapes.post("/me/shelves/:id", requireHead(), async (c) => {
  const head = c.get("head")!;
  const shelf = await store.shelf(c.env.NOTES, c.req.param("id"));
  if (!shelf || shelf.user_id !== head.id) return notFound(c);
  const form = await c.req.parseBody();
  await store.updateShelf(c.env.NOTES, head.id, shelf.id, { name: store.cleanName(String(form.name ?? ""), shelf.name), blurb: store.cleanBlurb(String(form.blurb ?? "")), isPrivate: form.is_private === "1" });
  return c.redirect(`/me/shelves/${shelf.id}?ok=1`, 303);
});

tapes.get("/me/shelves/:id/toss", requireHead(), async (c) => {
  const head = c.get("head")!;
  const shelf = await store.shelf(c.env.NOTES, c.req.param("id"));
  if (!shelf || shelf.user_id !== head.id) return notFound(c);
  const n = (await store.shelfItems(c.env.NOTES, shelf.id)).length;
  return c.html(render(<Frame title={`Toss ${shelf.name}?`} crumb={[head.handle, "shelves", shelf.name]} head={head} page="me">
    <Confirm title={`Toss “${shelf.name}”?`} body={`The shelf and its ${n} saved ${n === 1 ? "show go" : "shows go"} with it. The recordings stay in the archive.`} action={`/me/shelves/${shelf.id}/delete`} yes="Toss it" back={`/me/shelves/${shelf.id}`} />
  </Frame>));
});

tapes.post("/me/shelves/:id/delete", requireHead(), async (c) => {
  const head = c.get("head")!;
  const shelf = await store.shelf(c.env.NOTES, c.req.param("id"));
  if (!shelf || shelf.user_id !== head.id) return notFound(c);
  await store.deleteShelf(c.env.NOTES, head.id, shelf.id);
  return c.redirect("/me/shelves?ok=tossed", 303);
});

tapes.post("/me/shelves/:id/items/:item/delete", requireHead(), async (c) => {
  const head = c.get("head")!;
  await store.removeShelfItem(c.env.NOTES, head.id, c.req.param("id"), c.req.param("item"));
  return c.redirect(`/me/shelves/${c.req.param("id")}`, 303);
});

tapes.post("/me/shelves/:id/items/:item/move", requireHead(), async (c) => {
  const head = c.get("head")!;
  const form = await c.req.parseBody();
  const shelf = await store.shelf(c.env.NOTES, c.req.param("id"));
  if (!shelf || shelf.user_id !== head.id) return notFound(c);
  await store.moveItem(c.env.NOTES, head.id, "shelf_items", "shelf_id", shelf.id, c.req.param("item"), form.dir === "up" ? "up" : "down");
  return c.redirect(`/me/shelves/${shelf.id}`, 303);
});

// --- mix tapes -------------------------------------------------------------

tapes.get("/me/mixtapes", requireHead(), async (c) => {
  const head = c.get("head")!;
  const mixtapes = await q<store.Mixtape & { n: number; seconds: number }>(c.env.NOTES,
    `SELECT m.id, m.user_id, m.name, m.blurb, m.is_private, m.created_at, m.updated_at,
            (SELECT COUNT(*) FROM mixtape_items i WHERE i.mixtape_id=m.id AND i.deleted_at IS NULL) AS n,
            (SELECT COALESCE(SUM(duration_seconds),0) FROM mixtape_items i WHERE i.mixtape_id=m.id AND i.deleted_at IS NULL) AS seconds
     FROM mixtapes m WHERE m.user_id=? AND m.deleted_at IS NULL ORDER BY m.created_at`, head.id);
  const identifier = c.req.query("identifier"), file = c.req.query("file");
  const ok = c.req.query("ok") === "tossed" ? "Tossed." : null;
  return c.html(render(<Frame title="Mix Tapes" crumb={[head.handle, "mix tapes"]} head={head} page="me">
    <MeMixtapes head={head} mixtapes={mixtapes} ok={ok} error={c.req.query("error")} pending={identifier && file ? { identifier, file } : null} />
  </Frame>));
});

tapes.post("/me/mixtapes", requireHead(), async (c) => {
  const head = c.get("head")!;
  const form = await c.req.parseBody();
  const mixtape = await store.createMixtape(c.env.NOTES, head.id, store.cleanName(String(form.name ?? ""), "Mix Tape"));
  const identifier = String(form.identifier ?? ""), fileName = String(form.file_name ?? "");
  if (identifier && fileName) {
    const tune = (await store.resolveTune(c.env.CATALOG, identifier, fileName))
      ?? (await store.resolveTune(c.env.CATALOG, identifier, fileName, (await fetchTape(identifier, c.executionCtx, { needTracks: true }))?.tracks));
    if (tune) { await store.addTune(c.env.NOTES, head.id, mixtape.id, tune); return c.redirect(`/me/mixtapes/${mixtape.id}?ok=added`, 303); }
  }
  return c.redirect(`/me/mixtapes/${mixtape.id}`, 303);
});

/** "Put it on a mix tape" from a tape page. */
tapes.post("/me/mixtapes/add", requireHead(), async (c) => {
  const head = c.get("head")!;
  const form = await c.req.parseBody();
  const identifier = String(form.identifier ?? ""), fileName = String(form.file_name ?? ""), mixtapeId = String(form.mixtape_id ?? "");
  if (!identifier || !fileName) return notFound(c);
  if (mixtapeId === "new" || !mixtapeId) return c.redirect(`/me/mixtapes?identifier=${encodeURIComponent(identifier)}&file=${encodeURIComponent(fileName)}`, 303);
  const mixtape = await store.mixtape(c.env.NOTES, mixtapeId);
  if (!mixtape || mixtape.user_id !== head.id) return notFound(c);
  const catalogTune = await store.resolveTune(c.env.CATALOG, identifier, fileName);
  const tune = catalogTune ?? await store.resolveTune(c.env.CATALOG, identifier, fileName, (await fetchTape(identifier, c.executionCtx, { needTracks: true }))?.tracks);
  if (!tune) return c.redirect(`/me/mixtapes/${mixtape.id}?error=${encodeURIComponent("Couldn't find that tune on the tape.")}`, 303);
  const r = await store.addTune(c.env.NOTES, head.id, mixtape.id, tune);
  return c.redirect(`/me/mixtapes/${mixtape.id}?ok=${r}`, 303);
});

tapes.get("/me/mixtapes/:id", requireHead(), async (c) => {
  const head = c.get("head")!;
  const mixtape = await store.mixtape(c.env.NOTES, c.req.param("id"));
  if (!mixtape || mixtape.user_id !== head.id) return notFound(c);
  const [items, tree] = await Promise.all([store.mixtapeItems(c.env.NOTES, mixtape.id), treeFor(c.env.NOTES, "mixtape", mixtape.id, head.id)]);
  const ok = c.req.query("ok") === "added" ? "On the tape." : c.req.query("ok") === "already" ? "Already on it." : c.req.query("ok") === "1" ? "Saved." : null;
  return c.html(render(<Frame title={mixtape.name} crumb={[head.handle, "mix tapes", mixtape.name]} head={head} page="me"><MeMixtape head={head} mixtape={mixtape} items={items} tree={tree} ok={ok} error={c.req.query("error")} /></Frame>));
});

tapes.post("/me/mixtapes/:id", requireHead(), async (c) => {
  const head = c.get("head")!;
  const mixtape = await store.mixtape(c.env.NOTES, c.req.param("id"));
  if (!mixtape || mixtape.user_id !== head.id) return notFound(c);
  const form = await c.req.parseBody();
  await store.updateMixtape(c.env.NOTES, head.id, mixtape.id, { name: store.cleanName(String(form.name ?? ""), mixtape.name), blurb: store.cleanBlurb(String(form.blurb ?? "")), isPrivate: form.is_private === "1" });
  return c.redirect(`/me/mixtapes/${mixtape.id}?ok=1`, 303);
});

tapes.get("/me/mixtapes/:id/toss", requireHead(), async (c) => {
  const head = c.get("head")!;
  const mixtape = await store.mixtape(c.env.NOTES, c.req.param("id"));
  if (!mixtape || mixtape.user_id !== head.id) return notFound(c);
  return c.html(render(<Frame title={`Toss ${mixtape.name}?`} crumb={[head.handle, "mix tapes", mixtape.name]} head={head} page="me">
    <Confirm title={`Toss “${mixtape.name}”?`} body="The tunes stay on archive.org. Only the list goes." action={`/me/mixtapes/${mixtape.id}/delete`} yes="Toss it" back={`/me/mixtapes/${mixtape.id}`} />
  </Frame>));
});

tapes.post("/me/mixtapes/:id/delete", requireHead(), async (c) => {
  const head = c.get("head")!;
  const mixtape = await store.mixtape(c.env.NOTES, c.req.param("id"));
  if (!mixtape || mixtape.user_id !== head.id) return notFound(c);
  await store.deleteMixtape(c.env.NOTES, head.id, mixtape.id);
  return c.redirect("/me/mixtapes?ok=tossed", 303);
});

tapes.post("/me/mixtapes/:id/items/:item/delete", requireHead(), async (c) => {
  const head = c.get("head")!;
  await store.removeTune(c.env.NOTES, head.id, c.req.param("id"), c.req.param("item"));
  return c.redirect(`/me/mixtapes/${c.req.param("id")}`, 303);
});

tapes.post("/me/mixtapes/:id/items/:item/move", requireHead(), async (c) => {
  const head = c.get("head")!;
  const form = await c.req.parseBody();
  const mixtape = await store.mixtape(c.env.NOTES, c.req.param("id"));
  if (!mixtape || mixtape.user_id !== head.id) return notFound(c);
  await store.moveItem(c.env.NOTES, head.id, "mixtape_items", "mixtape_id", mixtape.id, c.req.param("item"), form.dir === "up" ? "up" : "down");
  return c.redirect(`/me/mixtapes/${mixtape.id}`, 303);
});

// --- public pages ----------------------------------------------------------

tapes.get("/heads/:handle{[^/.]+}/shelves/:id", async (c) => {
  const viewer = c.get("head");
  const shelf = await store.shelf(c.env.NOTES, c.req.param("id"));
  const owner = shelf ? await one<{ handle: string }>(c.env.NOTES, "SELECT handle FROM users WHERE id=? AND disabled_at IS NULL", shelf.user_id) : null;
  if (!shelf || !owner || owner.handle !== c.req.param("handle").toUpperCase()) return notFound(c);
  const mine = viewer?.id === shelf.user_id;
  if (shelf.is_private && !mine) return notFound(c);
  const [items, tree] = await Promise.all([store.shelfItems(c.env.NOTES, shelf.id), treeFor(c.env.NOTES, "shelf", shelf.id, viewer?.id ?? null)]);
  return c.html(render(<Frame title={shelf.name} crumb={[owner.handle, shelf.name]} head={viewer} page="tapelists"><ShelfPage owner={owner.handle} shelf={shelf} items={items} mine={mine} tree={tree} viewer={viewer} /></Frame>));
});

tapes.get("/heads/:handle{[^/.]+}/mixtapes/:id", async (c) => {
  const viewer = c.get("head");
  const mixtape = await store.mixtape(c.env.NOTES, c.req.param("id"));
  const owner = mixtape ? await one<{ handle: string }>(c.env.NOTES, "SELECT handle FROM users WHERE id=? AND disabled_at IS NULL", mixtape.user_id) : null;
  if (!mixtape || !owner || owner.handle !== c.req.param("handle").toUpperCase()) return notFound(c);
  const mine = viewer?.id === mixtape.user_id;
  if (mixtape.is_private && !mine) return notFound(c);
  const [items, tree] = await Promise.all([store.mixtapeItems(c.env.NOTES, mixtape.id), treeFor(c.env.NOTES, "mixtape", mixtape.id, viewer?.id ?? null)]);
  return c.html(render(<Frame title={mixtape.name} crumb={[owner.handle, mixtape.name]} head={viewer} page="tapelists"><MixtapePage owner={owner.handle} mixtape={mixtape} items={items} mine={mine} tree={tree} viewer={viewer} /></Frame>));
});

tapes.get("/tapelists", async (c) => {
  const [shelves, mixtapes, trees] = await Promise.all([
    q<{ id: string; name: string; owner: string; n: number; updated_at: string }>(c.env.NOTES,
      `SELECT s.id, s.name, u.handle AS owner, s.updated_at, (SELECT COUNT(*) FROM shelf_items i WHERE i.shelf_id=s.id AND i.deleted_at IS NULL) AS n
       FROM shelves s JOIN users u ON u.id=s.user_id WHERE s.deleted_at IS NULL AND s.is_private=0 AND u.disabled_at IS NULL ORDER BY s.updated_at DESC LIMIT 50`),
    q<{ id: string; name: string; owner: string; n: number; seconds: number; updated_at: string }>(c.env.NOTES,
      `SELECT m.id, m.name, u.handle AS owner, m.updated_at, (SELECT COUNT(*) FROM mixtape_items i WHERE i.mixtape_id=m.id AND i.deleted_at IS NULL) AS n,
              (SELECT COALESCE(SUM(duration_seconds),0) FROM mixtape_items i WHERE i.mixtape_id=m.id AND i.deleted_at IS NULL) AS seconds
       FROM mixtapes m JOIN users u ON u.id=m.user_id WHERE m.deleted_at IS NULL AND m.is_private=0 AND u.disabled_at IS NULL ORDER BY m.updated_at DESC LIMIT 50`),
    q<{ id: string; kind: string; name: string; owner: string; members: number }>(c.env.NOTES,
      `SELECT t.id, t.kind, COALESCE((SELECT name FROM shelves WHERE id=t.source_id), (SELECT name FROM mixtapes WHERE id=t.source_id)) AS name,
              (SELECT handle FROM users WHERE id=t.owner_id) AS owner, (SELECT COUNT(*) FROM tree_members m WHERE m.tree_id=t.id) AS members
       FROM trees t WHERE t.deleted_at IS NULL ORDER BY t.created_at DESC LIMIT 50`),
  ]);
  return c.html(render(<Frame title="Tape Lists" crumb={["Tape Lists"]} head={c.get("head")} page="tapelists"><TapeLists shelves={shelves} mixtapes={mixtapes} trees={trees} /></Frame>));
});

// --- journal ---------------------------------------------------------------

async function journalShow(c: any, raw: string): Promise<cat.CatalogShow | null> {
  const text = raw.trim();
  if (cat.SHOW_ID.test(text)) return cat.show(c.env.CATALOG, text);
  const iso = parseHeadDate(text);
  if (!iso || iso.length !== 10) return null;
  return (await cat.showsOnDate(c.env.CATALOG, iso))[0] ?? null;
}

tapes.get("/me/journal", requireHead(), async (c) => {
  const head = c.get("head")!;
  const entries = await store.journalEntries(c.env.NOTES, head.id);
  const showParam = c.req.query("show");
  const show = showParam ? await journalShow(c, showParam) : null;
  return c.html(render(<Frame title="Journal" crumb={[head.handle, "journal"]} head={head} page="me">
    <MeJournal head={head} entries={entries} show={show ? { show_id: show.show_id, label: `${prettyDate(show.date)} · ${show.venue ?? ""}` } : null} />
  </Frame>));
});

tapes.post("/me/journal", requireHead(), async (c) => {
  const head = c.get("head")!;
  const form = await c.req.parseBody();
  const raw = String(form.body ?? "");
  const show = await journalShow(c, String(form.show ?? ""));
  const cleaned = cleanBody(raw);
  const entries = await store.journalEntries(c.env.NOTES, head.id);
  const fail = (error: string) => c.html(render(<Frame title="Journal" crumb={[head.handle, "journal"]} head={head} page="me"><MeJournal head={head} entries={entries} error={error} draft={raw} /></Frame>), 400);
  if (!show) return fail("Which show? A date like 5/8/77.");
  if ("error" in cleaned) return fail(cleaned.error);
  const mood = String(form.mood ?? "").trim().slice(0, 30) || null;
  const id = await store.writeJournal(c.env.NOTES, head.id, show, cleaned.body, mood);
  return c.redirect(`/me/journal#j${id}`, 303);
});

tapes.get("/me/journal/:id", requireHead(), async (c) => {
  const head = c.get("head")!;
  const entry = await store.journalEntry(c.env.NOTES, head.id, c.req.param("id"));
  if (!entry) return notFound(c);
  return c.html(render(<Frame title={entry.show_display_name} crumb={[head.handle, "journal"]} head={head} page="me"><MeJournalEntry head={head} entry={entry} /></Frame>));
});

tapes.post("/me/journal/:id", requireHead(), async (c) => {
  const head = c.get("head")!;
  const entry = await store.journalEntry(c.env.NOTES, head.id, c.req.param("id"));
  if (!entry) return notFound(c);
  const form = await c.req.parseBody();
  const cleaned = cleanBody(String(form.body ?? ""));
  if ("error" in cleaned) return c.html(render(<Frame title={entry.show_display_name} crumb={[head.handle, "journal"]} head={head} page="me"><MeJournalEntry head={head} entry={entry} error={cleaned.error} /></Frame>), 400);
  await store.updateJournal(c.env.NOTES, head.id, entry.id, cleaned.body, String(form.mood ?? "").trim().slice(0, 30) || null);
  return c.redirect(`/me/journal#j${entry.id}`, 303);
});

tapes.post("/me/journal/:id/delete", requireHead(), async (c) => {
  const head = c.get("head")!;
  await store.deleteJournal(c.env.NOTES, head.id, c.req.param("id"));
  return c.redirect("/me/journal", 303);
});
