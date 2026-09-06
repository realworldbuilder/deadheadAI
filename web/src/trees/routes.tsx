/** Trees: start one from a shelf or mix tape, get on, get off, close it; and the feed. */
import { Hono } from "hono";
import type { App } from "../env";
import { requireHead } from "../auth/sessions";
import { nowIso, uuid } from "../db/ids";
import { one, q, stmt } from "../db/notes";
import * as store from "../tapes/store";
import { Frame, render } from "../views/frame";
import { NotFound } from "../views/errors";
import { OnTheTree, TreePage, type FeedRow, type TreeRow } from "../views/tree";

export const trees = new Hono<App>();

function treeById(db: D1Database, id: string) {
  return one<TreeRow>(db,
    `SELECT t.id, t.owner_id, u.handle AS owner, t.kind, t.source_id, t.created_at,
            COALESCE((SELECT name FROM shelves WHERE id=t.source_id AND deleted_at IS NULL), (SELECT name FROM mixtapes WHERE id=t.source_id AND deleted_at IS NULL)) AS name,
            COALESCE((SELECT blurb FROM shelves WHERE id=t.source_id), (SELECT blurb FROM mixtapes WHERE id=t.source_id), '') AS blurb
     FROM trees t JOIN users u ON u.id=t.owner_id WHERE t.id=? AND t.deleted_at IS NULL`, id);
}

async function startTree(c: any, kind: "shelf" | "mixtape", sourceId: string) {
  const head = c.get("head")!;
  const source = kind === "shelf" ? await store.shelf(c.env.NOTES, sourceId) : await store.mixtape(c.env.NOTES, sourceId);
  if (!source || source.user_id !== head.id) return c.notFound();
  if (source.is_private) return c.redirect(`/me/${kind === "shelf" ? "shelves" : "mixtapes"}/${sourceId}?error=${encodeURIComponent("Make it public first, then start the tree.")}`, 303);
  const existing = await one<{ id: string }>(c.env.NOTES, "SELECT id FROM trees WHERE kind=? AND source_id=? AND deleted_at IS NULL", kind, sourceId);
  if (existing) return c.redirect(`/trees/${existing.id}`, 303);
  const id = uuid();
  // A closed tree on the same source is reopened rather than duplicated: the UNIQUE(kind, source_id) says so.
  const closed = await one<{ id: string }>(c.env.NOTES, "SELECT id FROM trees WHERE kind=? AND source_id=?", kind, sourceId);
  if (closed) {
    await stmt(c.env.NOTES, "UPDATE trees SET deleted_at=NULL, created_at=? WHERE id=?", nowIso(), closed.id).run();
    return c.redirect(`/trees/${closed.id}`, 303);
  }
  await stmt(c.env.NOTES, "INSERT INTO trees (id, owner_id, kind, source_id, created_at) VALUES (?,?,?,?,?)", id, head.id, kind, sourceId, nowIso()).run();
  return c.redirect(`/trees/${id}`, 303);
}

trees.post("/me/shelves/:id/tree", requireHead(), (c) => startTree(c, "shelf", c.req.param("id")));
trees.post("/me/mixtapes/:id/tree", requireHead(), (c) => startTree(c, "mixtape", c.req.param("id")));

trees.get("/trees/:id", async (c) => {
  const viewer = c.get("head");
  const tree = await treeById(c.env.NOTES, c.req.param("id"));
  if (!tree || !tree.name) return c.html(render(<Frame title="Nothing here" crumb={["Trees"]} head={viewer} page="tapelists"><NotFound /></Frame>), 404);
  const [shelfItems, mixItems, members, joined] = await Promise.all([
    tree.kind === "shelf" ? store.shelfItems(c.env.NOTES, tree.source_id) : Promise.resolve([]),
    tree.kind === "mixtape" ? store.mixtapeItems(c.env.NOTES, tree.source_id) : Promise.resolve([]),
    q<{ handle: string; joined_at: string }>(c.env.NOTES, "SELECT u.handle, m.joined_at FROM tree_members m JOIN users u ON u.id=m.user_id WHERE m.tree_id=? ORDER BY m.joined_at", tree.id),
    viewer ? one(c.env.NOTES, "SELECT 1 AS x FROM tree_members WHERE tree_id=? AND user_id=?", tree.id, viewer.id) : Promise.resolve(null),
  ]);
  return c.html(render(<Frame title={tree.name} crumb={["Tape Lists", tree.name]} head={viewer} page="tapelists">
    <TreePage tree={tree} shelfItems={shelfItems} mixItems={mixItems} members={members} viewer={viewer} joined={!!joined} />
  </Frame>));
});

trees.post("/trees/:id/join", requireHead(), async (c) => {
  const head = c.get("head")!;
  const tree = await treeById(c.env.NOTES, c.req.param("id"));
  if (!tree) return c.notFound();
  if (tree.owner_id !== head.id) {
    await stmt(c.env.NOTES, "INSERT OR IGNORE INTO tree_members (tree_id, user_id, joined_at) VALUES (?,?,?)", tree.id, head.id, nowIso()).run();
  }
  return c.redirect(`/trees/${tree.id}`, 303);
});

trees.post("/trees/:id/leave", requireHead(), async (c) => {
  const head = c.get("head")!;
  await stmt(c.env.NOTES, "DELETE FROM tree_members WHERE tree_id=? AND user_id=?", c.req.param("id"), head.id).run();
  return c.redirect(`/trees/${c.req.param("id")}`, 303);
});

trees.post("/trees/:id/close", requireHead(), async (c) => {
  const head = c.get("head")!;
  const tree = await treeById(c.env.NOTES, c.req.param("id"));
  if (!tree) return c.notFound();
  if (tree.owner_id !== head.id && !head.isAdmin) return c.notFound();
  await stmt(c.env.NOTES, "UPDATE trees SET deleted_at=? WHERE id=?", nowIso(), tree.id).run();
  return c.redirect(tree.kind === "shelf" ? `/me/shelves/${tree.source_id}` : `/me/mixtapes/${tree.source_id}`, 303);
});

trees.get("/me/tree", requireHead(), async (c) => {
  const head = c.get("head")!;
  const mine = await q<{ id: string; name: string; owner: string }>(c.env.NOTES,
    `SELECT t.id, COALESCE((SELECT name FROM shelves WHERE id=t.source_id), (SELECT name FROM mixtapes WHERE id=t.source_id)) AS name, u.handle AS owner
     FROM tree_members m JOIN trees t ON t.id=m.tree_id JOIN users u ON u.id=t.owner_id WHERE m.user_id=? AND t.deleted_at IS NULL ORDER BY m.joined_at DESC`, head.id);
  const rows = await q<FeedRow>(c.env.NOTES,
    `SELECT t.id AS tree_id, (SELECT name FROM shelves WHERE id=t.source_id) AS tree_name, u.handle AS owner, t.kind,
            i.show_id, i.show_identifier, i.display_name AS label, i.added_at, NULL AS file_name, i.show_date
     FROM tree_members m JOIN trees t ON t.id=m.tree_id JOIN users u ON u.id=t.owner_id
     JOIN shelf_items i ON i.shelf_id=t.source_id AND i.deleted_at IS NULL AND i.added_at > m.joined_at
     WHERE m.user_id=? AND t.kind='shelf' AND t.deleted_at IS NULL
     UNION ALL
     SELECT t.id, (SELECT name FROM mixtapes WHERE id=t.source_id), u.handle, t.kind,
            NULL, i.show_identifier, i.track_title, i.added_at, i.file_name, i.show_date_string
     FROM tree_members m JOIN trees t ON t.id=m.tree_id JOIN users u ON u.id=t.owner_id
     JOIN mixtape_items i ON i.mixtape_id=t.source_id AND i.deleted_at IS NULL AND i.added_at > m.joined_at
     WHERE m.user_id=? AND t.kind='mixtape' AND t.deleted_at IS NULL
     ORDER BY added_at DESC LIMIT 50`, head.id, head.id);
  return c.html(render(<Frame title="On the Tree" crumb={[head.handle, "on the tree"]} head={head} page="me"><OnTheTree rows={rows.map((r) => ({ ...r, label: r.kind === "shelf" ? r.label.replace(/^\S+\s*/, "") : r.label }))} trees={mine} /></Frame>));
});
