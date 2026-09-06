/** The back room: counts, heads, notes. Admins only; everyone else sees a 404. */
import { Hono } from "hono";
import type { App } from "../env";
import { requireAdmin } from "../auth/sessions";
import { nowIso } from "../db/ids";
import { one, q, stmt } from "../db/notes";
import * as cat from "../catalog/queries";
import { eraseHead } from "../me/routes";
import { parseHandle } from "../auth/handles";
import { Frame, render } from "../views/frame";
import { AdminHeads, AdminHome, AdminNotes, type AdminCounts, type AdminHead, type AdminNote } from "../views/admin";

export const admin = new Hono<App>();

admin.use("/admin/*", requireAdmin());
admin.use("/admin", requireAdmin());

admin.get("/admin", async (c) => {
  const head = c.get("head")!;
  const [counts, catalog] = await Promise.all([
    one<AdminCounts>(c.env.NOTES,
      `SELECT (SELECT COUNT(*) FROM users) AS heads, (SELECT COUNT(*) FROM notes WHERE deleted_at IS NULL) AS notes,
              (SELECT COUNT(*) FROM shelves WHERE deleted_at IS NULL) AS shelves, (SELECT COUNT(*) FROM mixtapes WHERE deleted_at IS NULL) AS mixtapes,
              (SELECT COUNT(*) FROM trees WHERE deleted_at IS NULL) AS trees,
              (SELECT COUNT(*) FROM spins WHERE updated_at > ?) AS spins24h,
              (SELECT COUNT(*) FROM sessions WHERE expires_at > ?) AS sessions`,
      new Date(Date.now() - 86400000).toISOString(), nowIso()),
    cat.meta(c.env.CATALOG),
  ]);
  return c.html(render(<Frame title="Admin" crumb={["Admin"]} head={head} page="admin"><AdminHome head={head} counts={counts!} catalog={catalog} /></Frame>));
});

admin.get("/admin/heads", async (c) => {
  const head = c.get("head")!;
  const qtext = (c.req.query("q") ?? "").trim().toUpperCase();
  const rows = await q<AdminHead>(c.env.NOTES,
    `SELECT u.id, u.handle, u.created_at, u.disabled_at, u.role,
            (SELECT COUNT(*) FROM notes n WHERE n.user_id=u.id AND n.deleted_at IS NULL) AS notes,
            (SELECT COUNT(*) FROM passkeys p WHERE p.user_id=u.id) AS passkeys,
            (SELECT MAX(last_seen_at) FROM sessions s WHERE s.user_id=u.id) AS last_seen
     FROM users u WHERE u.handle LIKE ? ORDER BY u.created_at DESC LIMIT 200`, `%${qtext}%`);
  const ok = c.req.query("ok") ?? null;
  return c.html(render(<Frame title="Heads" crumb={["Admin", "heads"]} head={head} page="admin"><AdminHeads heads={rows} q={qtext} ok={ok} /></Frame>));
});

async function headByParam(c: any) {
  const parsed = parseHandle(c.req.param("handle"), { allowReserved: true });
  if ("error" in parsed) return null;
  return one<{ id: string; handle: string }>(c.env.NOTES, "SELECT id, handle FROM users WHERE handle=?", parsed.handle);
}

admin.post("/admin/heads/:handle/disable", async (c) => {
  const target = await headByParam(c);
  if (!target) return c.notFound();
  await c.env.NOTES.batch([
    stmt(c.env.NOTES, "UPDATE users SET disabled_at=?, updated_at=? WHERE id=?", nowIso(), nowIso(), target.id),
    stmt(c.env.NOTES, "DELETE FROM sessions WHERE user_id=?", target.id),
    stmt(c.env.NOTES, "DELETE FROM spins WHERE user_id=?", target.id),
  ]);
  return c.redirect(`/admin/heads?ok=${encodeURIComponent(`${target.handle} frozen.`)}`, 303);
});

admin.post("/admin/heads/:handle/enable", async (c) => {
  const target = await headByParam(c);
  if (!target) return c.notFound();
  await stmt(c.env.NOTES, "UPDATE users SET disabled_at=NULL, updated_at=? WHERE id=?", nowIso(), target.id).run();
  return c.redirect(`/admin/heads?ok=${encodeURIComponent(`${target.handle} thawed.`)}`, 303);
});

admin.post("/admin/heads/:handle/delete", async (c) => {
  const target = await headByParam(c);
  if (!target) return c.notFound();
  const form = await c.req.parseBody();
  if (String(form.confirm_handle ?? "").trim().toUpperCase() !== target.handle) {
    return c.redirect(`/admin/heads?ok=${encodeURIComponent("Type the handle exactly to erase a head.")}`, 303);
  }
  await eraseHead(c.env.NOTES, target.id, target.handle);
  return c.redirect(`/admin/heads?ok=${encodeURIComponent(`${target.handle} erased.`)}`, 303);
});

admin.get("/admin/notes", async (c) => {
  const head = c.get("head")!;
  const before = Number(c.req.query("before") ?? 0) || null;
  const rows = before
    ? await q<AdminNote>(c.env.NOTES, "SELECT n.id, n.topic_id, n.reply_no, n.handle, t.show_id, n.created_at, n.deleted_by, n.body FROM notes n JOIN topics t ON t.id=n.topic_id WHERE n.id<? ORDER BY n.id DESC LIMIT 51", before)
    : await q<AdminNote>(c.env.NOTES, "SELECT n.id, n.topic_id, n.reply_no, n.handle, t.show_id, n.created_at, n.deleted_by, n.body FROM notes n JOIN topics t ON t.id=n.topic_id ORDER BY n.id DESC LIMIT 51");
  const page = rows.slice(0, 50);
  return c.html(render(<Frame title="Notes" crumb={["Admin", "notes"]} head={head} page="admin"><AdminNotes notes={page} older={rows.length > 50 ? page[page.length - 1]!.id : null} ok={c.req.query("ok") ?? null} /></Frame>));
});

admin.post("/admin/notes/:ref{\\d+\\.\\d+}/delete", async (c) => {
  const [topic, reply] = c.req.param("ref").split(".").map(Number);
  const note = await one<{ id: number; topic_id: number }>(c.env.NOTES, "SELECT id, topic_id FROM notes WHERE topic_id=? AND reply_no=? AND deleted_at IS NULL", topic, reply);
  if (!note) return c.notFound();
  await c.env.NOTES.batch([
    stmt(c.env.NOTES, "UPDATE notes SET body='', deleted_at=?, deleted_by='admin' WHERE id=?", nowIso(), note.id),
    stmt(c.env.NOTES, "UPDATE topics SET note_count=note_count-1 WHERE id=? AND note_count>0", note.topic_id),
  ]);
  return c.redirect(`/admin/notes?ok=${encodeURIComponent(`${c.req.param("ref")} pulled.`)}`, 303);
});
