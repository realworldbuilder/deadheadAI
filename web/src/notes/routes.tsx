/** The conference: write a note on a show, read them newest first, one at a time. */
import { Hono } from "hono";
import type { App } from "../env";
import * as cat from "../catalog/queries";
import { requireHead } from "../auth/sessions";
import { nowIso } from "../db/ids";
import { one, q, stmt } from "../db/notes";
import { parseNoteRef } from "../fmt";
import { Frame, render } from "../views/frame";
import { NoteEdit, NoteSingle, NotesIndex, type NoteRow } from "../views/notes";
import { NotFound } from "../views/errors";
import { topicPage } from "../shows/routes";
import { cleanBody, ensureTopic, mintReply, topicById } from "./numbering";
import { checkNoteRate } from "./ratelimit";

export const notes = new Hono<App>();

const NOTE_COLS = "n.id, n.topic_id, n.reply_no, n.user_id, n.handle, n.body, n.created_at, n.edited_at, n.deleted_at, n.deleted_by, t.show_id, t.title";
export const EDIT_WINDOW_MS = 15 * 60000;

notes.get("/notes", async (c) => {
  const head = c.get("head");
  const before = Number(c.req.query("before") ?? 0) || null;
  const rows = before
    ? await q<NoteRow>(c.env.NOTES, `SELECT ${NOTE_COLS} FROM notes n JOIN topics t ON t.id=n.topic_id WHERE n.id < ? ORDER BY n.id DESC LIMIT 26`, before)
    : await q<NoteRow>(c.env.NOTES, `SELECT ${NOTE_COLS} FROM notes n JOIN topics t ON t.id=n.topic_id ORDER BY n.id DESC LIMIT 26`);
  const page = rows.slice(0, 25);
  const older = rows.length > 25 ? page[page.length - 1]!.id : null;
  const seenThrough = head?.notesSeenThrough ?? 0;
  if (head && !before && page.length && page[0]!.id > seenThrough) {
    c.executionCtx.waitUntil(stmt(c.env.NOTES, "UPDATE users SET notes_seen_through=? WHERE id=?", page[0]!.id, head.id).run());
  }
  return c.html(render(<Frame title="Notes" crumb={["Notes"]} head={head} page="notes"><NotesIndex notes={page} seenThrough={seenThrough} before={before} older={older} head={head} /></Frame>));
});

async function noteByRef(db: D1Database, ref: string): Promise<NoteRow | null> {
  const parsed = parseNoteRef(ref);
  if (!parsed) return null;
  return one<NoteRow>(db, `SELECT ${NOTE_COLS} FROM notes n JOIN topics t ON t.id=n.topic_id WHERE n.topic_id=? AND n.reply_no=?`, parsed.topic, parsed.reply);
}

notes.get("/notes/:ref{\\d+\\.\\d+}", async (c) => {
  const head = c.get("head");
  const ref = c.req.param("ref");
  const parsed = parseNoteRef(ref)!;
  if (parsed.reply === 0) {
    const topic = await topicById(c.env.NOTES, parsed.topic);
    return topic ? c.redirect(`/shows/${topic.show_id}`, 302) : c.notFound();
  }
  const note = await noteByRef(c.env.NOTES, ref);
  if (!note) return c.html(render(<Frame title="Nothing here" crumb={["Notes"]} head={head} page="notes"><NotFound /></Frame>), 404);
  const [prev, next] = await Promise.all([
    one<{ r: number }>(c.env.NOTES, "SELECT MAX(reply_no) AS r FROM notes WHERE topic_id=? AND reply_no<?", note.topic_id, note.reply_no),
    one<{ r: number }>(c.env.NOTES, "SELECT MIN(reply_no) AS r FROM notes WHERE topic_id=? AND reply_no>?", note.topic_id, note.reply_no),
  ]);
  const mine = !!head && head.id === note.user_id && !note.deleted_at;
  const canEdit = mine && Date.now() - new Date(note.created_at).getTime() < EDIT_WINDOW_MS;
  const canPull = (mine || (!!head?.isAdmin && !note.deleted_at));
  return c.html(render(<Frame title={`Note ${ref}`} crumb={["GRATEFUL " + ref]} head={head} page="notes">
    <NoteSingle note={note} prev={prev?.r ?? null} next={next?.r ?? null} head={head} canEdit={canEdit} canPull={canPull} />
  </Frame>));
});

notes.post("/shows/:id{\\d{4}-\\d{2}-\\d{2}(?:-early|-late)?}/notes", requireHead(), async (c) => {
  const head = c.get("head")!;
  const show = await cat.show(c.env.CATALOG, c.req.param("id"));
  if (!show) return c.notFound();
  const form = await c.req.parseBody();
  const raw = String(form.body ?? "");
  const cleaned = cleanBody(raw);
  if ("error" in cleaned) return c.html(render(await topicPage(c, show, head, cleaned.error, raw)), 400);
  const rate = await checkNoteRate(c.env.NOTES, head.id);
  if (rate === "daily") return c.html(render(await topicPage(c, show, head, "Thirty notes in a day is plenty. Spin a tape and come back tomorrow.", raw)), 429);
  if (rate === "burst") return c.html(render(await topicPage(c, show, head, "Easy. One note every twenty seconds.", raw)), 429);
  const topic = await ensureTopic(c.env.NOTES, show);
  const minted = await mintReply(c.env.NOTES, topic.id, head.id, head.handle, cleaned.body);
  return c.redirect(`/notes/${topic.id}.${minted.reply_no}`, 303);
});

notes.get("/notes/:ref{\\d+\\.\\d+}/edit", requireHead(), async (c) => {
  const head = c.get("head")!;
  const note = await noteByRef(c.env.NOTES, c.req.param("ref"));
  if (!note || note.user_id !== head.id || note.deleted_at) return c.notFound();
  if (Date.now() - new Date(note.created_at).getTime() >= EDIT_WINDOW_MS) return c.redirect(`/notes/${c.req.param("ref")}`, 303);
  return c.html(render(<Frame title={`Edit ${c.req.param("ref")}`} crumb={["Notes", c.req.param("ref")]} head={head} page="notes"><NoteEdit note={note} /></Frame>));
});

notes.post("/notes/:ref{\\d+\\.\\d+}/edit", requireHead(), async (c) => {
  const head = c.get("head")!;
  const ref = c.req.param("ref");
  const note = await noteByRef(c.env.NOTES, ref);
  if (!note || note.user_id !== head.id || note.deleted_at) return c.notFound();
  if (Date.now() - new Date(note.created_at).getTime() >= EDIT_WINDOW_MS) {
    return c.html(render(<Frame title={`Edit ${ref}`} crumb={["Notes", ref]} head={head} page="notes"><NoteEdit note={note} error="The fifteen minutes are up. The note stands." /></Frame>), 403);
  }
  const form = await c.req.parseBody();
  const raw = String(form.body ?? "");
  const cleaned = cleanBody(raw);
  if ("error" in cleaned) return c.html(render(<Frame title={`Edit ${ref}`} crumb={["Notes", ref]} head={head} page="notes"><NoteEdit note={note} error={cleaned.error} draft={raw} /></Frame>), 400);
  await stmt(c.env.NOTES, "UPDATE notes SET body=?, edited_at=? WHERE id=?", cleaned.body, nowIso(), note.id).run();
  return c.redirect(`/notes/${ref}`, 303);
});

notes.post("/notes/:ref{\\d+\\.\\d+}/delete", requireHead(), async (c) => {
  const head = c.get("head")!;
  const ref = c.req.param("ref");
  const note = await noteByRef(c.env.NOTES, ref);
  if (!note || note.deleted_at) return c.notFound();
  const mine = note.user_id === head.id;
  if (!mine && !head.isAdmin) return c.notFound();
  await c.env.NOTES.batch([
    stmt(c.env.NOTES, "UPDATE notes SET body='', deleted_at=?, deleted_by=? WHERE id=?", nowIso(), mine ? "author" : "admin", note.id),
    stmt(c.env.NOTES, "UPDATE topics SET note_count=note_count-1 WHERE id=? AND note_count>0", note.topic_id),
  ]);
  return c.redirect(`/notes/${ref}`, 303);
});
