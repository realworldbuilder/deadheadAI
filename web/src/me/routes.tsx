/** Your page, and the way off the bus. */
import { Hono } from "hono";
import type { App } from "../env";
import { requireHead, revokeCurrent } from "../auth/sessions";
import { nowIso } from "../db/ids";
import { one, stmt } from "../db/notes";
import { parseHeadDate } from "../fmt";
import { Frame, render } from "../views/frame";
import { LeaveBus, Me } from "../views/me";
import { identityProviders } from "../auth/apple";
import { parseHandle } from "../auth/handles";

export const me = new Hono<App>();

async function counts(db: D1Database, userId: string) {
  const row = await one<{ notes: number; shelves: number; mixtapes: number; journal: number; passkeys: number }>(db,
    `SELECT (SELECT COUNT(*) FROM notes WHERE user_id=? AND deleted_at IS NULL) AS notes,
            (SELECT COUNT(*) FROM shelves WHERE user_id=? AND deleted_at IS NULL) AS shelves,
            (SELECT COUNT(*) FROM mixtapes WHERE user_id=? AND deleted_at IS NULL) AS mixtapes,
            (SELECT COUNT(*) FROM journal_entries WHERE user_id=? AND deleted_at IS NULL) AS journal,
            (SELECT COUNT(*) FROM passkeys WHERE user_id=?) AS passkeys`, userId, userId, userId, userId, userId);
  return row ?? { notes: 0, shelves: 0, mixtapes: 0, journal: 0, passkeys: 0 };
}

me.get("/me", requireHead(), async (c) => {
  const head = c.get("head")!;
  const n = await counts(c.env.NOTES, head.id);
  const providers = await identityProviders(c.env.NOTES, head.id);
  return c.html(render(<Frame title={head.handle} crumb={[head.handle]} head={head} page="me">
    <Me head={head} saved={c.req.query("saved") === "1"} welcome={c.req.query("welcome") === "1"} passkeyCount={n.passkeys} counts={n} providers={providers} canRename={providers.includes("apple") && n.notes === 0} />
  </Frame>));
});

me.post("/me", requireHead(), async (c) => {
  const head = c.get("head")!;
  const form = await c.req.parseBody();
  const raw = String(form.first_show ?? "").trim();
  let firstShow: string | null = null;
  if (raw) {
    firstShow = parseHeadDate(raw);
    const year = firstShow ? Number(firstShow.slice(0, 4)) : 0;
    if (!firstShow || year < 1965 || year > 1995) {
      const n = await counts(c.env.NOTES, head.id);
      return c.html(render(<Frame title={head.handle} crumb={[head.handle]} head={head} page="me">
        <Me head={head} error="That date didn't parse. Try 5/8/77, or just a year between '65 and '95." passkeyCount={n.passkeys} counts={n} providers={[]} />
      </Frame>), 400);
    }
  }
  const share = form.share_spins === "1" ? 1 : 0;
  await stmt(c.env.NOTES, "UPDATE users SET first_show=?, share_spins=?, updated_at=? WHERE id=?", firstShow, share, nowIso(), head.id).run();
  if (!share) await stmt(c.env.NOTES, "DELETE FROM spins WHERE user_id=?", head.id).run();
  return c.redirect("/me?saved=1", 303);
});

/** A head who came in with Apple got a handle picked for them; they can change it once, before they've written anything. */
me.post("/me/handle", requireHead(), async (c) => {
  const head = c.get("head")!;
  const form = await c.req.parseBody();
  const notes = await one<{ n: number }>(c.env.NOTES, "SELECT COUNT(*) AS n FROM notes WHERE user_id=?", head.id);
  if ((notes?.n ?? 0) > 0) return c.redirect("/me", 303);
  const parsed = parseHandle(String(form.handle ?? ""));
  const n = await counts(c.env.NOTES, head.id);
  const fail = (error: string) => c.html(render(<Frame title={head.handle} crumb={[head.handle]} head={head} page="me"><Me head={head} error={error} passkeyCount={n.passkeys} counts={n} providers={[]} /></Frame>), 400);
  if ("error" in parsed) return fail(parsed.error);
  const taken = await one(c.env.NOTES, "SELECT 1 AS x FROM users WHERE handle=? AND id<>?", parsed.handle, head.id);
  if (taken) return fail(`${parsed.handle} is taken. Try another.`);
  await c.env.NOTES.batch([
    stmt(c.env.NOTES, "UPDATE users SET handle=?, node=?, name=?, updated_at=? WHERE id=?", parsed.handle, parsed.node, parsed.name, nowIso(), head.id),
    stmt(c.env.NOTES, "UPDATE spins SET handle=? WHERE user_id=?", parsed.handle, head.id),
  ]);
  return c.redirect("/me?saved=1", 303);
});

me.get("/me/delete", requireHead(), (c) => {
  const head = c.get("head")!;
  return c.html(render(<Frame title="Leave the bus" crumb={[head.handle, "leave"]} head={head} page="me"><LeaveBus head={head} /></Frame>));
});

me.post("/me/delete", requireHead(), async (c) => {
  const head = c.get("head")!;
  const form = await c.req.parseBody();
  if (String(form.confirm_handle ?? "").trim().toUpperCase() !== head.handle) {
    return c.html(render(<Frame title="Leave the bus" crumb={[head.handle, "leave"]} head={head} page="me"><LeaveBus head={head} error="That's not your handle. Type it exactly, NODE::NAME." /></Frame>), 400);
  }
  await eraseHead(c.env.NOTES, head.id, head.handle);
  await revokeCurrent(c);
  return c.redirect("/", 303);
});

/** Everything about a head goes, except their notes, which stay in the conference with no name on them. */
export async function eraseHead(db: D1Database, userId: string, handle: string): Promise<void> {
  const now = nowIso();
  await db.batch([
    stmt(db, "UPDATE notes SET user_id=NULL, handle=NULL, body='', deleted_at=COALESCE(deleted_at, ?), deleted_by=COALESCE(deleted_by, 'erased') WHERE user_id=?", now, userId),
    stmt(db, "UPDATE topics SET note_count=(SELECT COUNT(*) FROM notes WHERE notes.topic_id=topics.id AND deleted_at IS NULL)"),
    stmt(db, "DELETE FROM tree_members WHERE user_id=?", userId),
    stmt(db, "DELETE FROM trees WHERE owner_id=?", userId),
    stmt(db, "DELETE FROM spins WHERE user_id=?", userId),
    stmt(db, "DELETE FROM mixtape_items WHERE user_id=?", userId),
    stmt(db, "DELETE FROM mixtapes WHERE user_id=?", userId),
    stmt(db, "DELETE FROM shelf_items WHERE user_id=?", userId),
    stmt(db, "DELETE FROM shelves WHERE user_id=?", userId),
    stmt(db, "DELETE FROM journal_entries WHERE user_id=?", userId),
    stmt(db, "DELETE FROM ceremonies WHERE user_id=? OR (kind='recovery_fail' AND payload_json=?)", userId, handle),
    stmt(db, "DELETE FROM sessions WHERE user_id=?", userId),
    stmt(db, "DELETE FROM passkeys WHERE user_id=?", userId),
    stmt(db, "DELETE FROM identities WHERE user_id=?", userId),
    stmt(db, "DELETE FROM users WHERE id=?", userId),
  ]);
}
