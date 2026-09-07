/** Recent notes, one note, and the body renderer that links dates and handles. */
import type { FC } from "hono/jsx";
import type { Head } from "../env";
import { noteNumber, parseHeadDate, prettyDate } from "../fmt";
import { Empty, Err, NoteBlock } from "./parts";

export interface NoteRow {
  id: number; topic_id: number; reply_no: number; user_id: string | null; handle: string | null; body: string;
  created_at: string; edited_at: string | null; deleted_at: string | null; deleted_by: string | null;
  show_id: string; title: string;
}

const LINKY = /(\b\d{1,2}\/\d{1,2}\/\d{2}\b|\b[A-Z0-9_]{2,12}::[A-Z0-9_]{2,12}\b)/g;

/** Plain text with 5/8/77 and NODE::NAME turned into links. Everything else stays text. */
export const NoteBody: FC<{ body: string }> = ({ body }) => {
  const parts = body.split(LINKY);
  return (
    <pre>
      {parts.map((part, i) => {
        if (i % 2 === 0) return part;
        if (part.includes("::")) return <a href={`/heads/${part}`}>{part}</a>;
        const iso = parseHeadDate(part);
        return iso && iso.length === 10 ? <a href={`/shows/${iso}`}>{part}</a> : part;
      })}
    </pre>
  );
};

export function showLabel(title: string): string {
  return title.split(" · ").slice(0, 2).join(" ");
}

export const NotesIndex: FC<{ notes: NoteRow[]; seenThrough: number; before: number | null; older: number | null; head: Head | null }> = ({ notes, seenThrough, older, head }) => (
  <>
    <h1>Notes</h1>
    <p class="sub">Newest first. Every show is a topic; the number is the topic and the reply.</p>
    {notes.length === 0 ? <Empty>Nobody's written a note yet. Open any show and be the first.</Empty> : null}
    {notes.map((n) => (
      <div class={head && n.id > seenThrough ? "unseen" : undefined}>
        <NoteBlock handle={n.handle} ref={noteNumber(n.topic_id, n.reply_no)} href={`/notes/${noteNumber(n.topic_id, n.reply_no)}`} stamp={n.created_at}
          body={n.body} deleted={n.deleted_by} showLink={{ href: `/shows/${n.show_id}`, label: showLabel(n.title) }} />
      </div>
    ))}
    {older ? <p class="meta"><a href={`/notes?before=${older}`}>Older notes →</a></p> : null}
  </>
);

export const NoteSingle: FC<{ note: NoteRow; prev: number | null; next: number | null; head: Head | null; canEdit: boolean; canPull: boolean }> = ({ note, prev, next, head, canEdit, canPull }) => {
  const ref = noteNumber(note.topic_id, note.reply_no);
  return (
    <>
      <h1 class="topic">Note {ref}</h1>
      <p class="meta">Topic {note.topic_id} · <a href={`/shows/${note.show_id}`}>{note.title}</a></p>
      <div class="note" id={`n${ref}`}>
        <div class="hdr"><b>{note.handle ? <a href={`/heads/${note.handle}`}>{note.handle}</a> : "—"}</b> · GRATEFUL {ref} · {stamp(note.created_at)}{note.edited_at ? " · edited" : ""}</div>
        {note.deleted_by
          ? <p class="empty">{note.deleted_by === "admin" ? "Note pulled by the admin." : note.deleted_by === "erased" ? "This head left the bus; the note went with them." : "Note pulled by its author."}</p>
          : <NoteBody body={note.body} />}
      </div>
      <div class="btns">
        {head ? <a class="btn btn-red" href={`/shows/${note.show_id}#write`}>Reply</a> : null}
        <a class="btn" href={`/shows/${note.show_id}#notes`}>The topic</a>
        {canEdit ? <a class="btn" href={`/notes/${ref}/edit`}>Edit</a> : null}
        {canPull ? <form method="post" action={`/notes/${ref}/delete`} class="inline"><button class="btn" type="submit">Pull the note</button></form> : null}
      </div>
      <p class="meta nav2">
        {prev ? <a href={`/notes/${noteNumber(note.topic_id, prev)}`}>← {noteNumber(note.topic_id, prev)}</a> : null}
        {prev && next ? " · " : ""}
        {next ? <a href={`/notes/${noteNumber(note.topic_id, next)}`}>{noteNumber(note.topic_id, next)} →</a> : null}
      </p>
    </>
  );
};

export const NoteEdit: FC<{ note: NoteRow; error?: string | null; draft?: string }> = ({ note, error, draft }) => {
  const ref = noteNumber(note.topic_id, note.reply_no);
  return (
    <>
      <h1 class="topic">Edit {ref}</h1>
      <p class="meta">You've got fifteen minutes after posting to fix a note. After that it stands.</p>
      {error ? <Err>{error}</Err> : null}
      <form method="post" action={`/notes/${ref}/edit`}>
        <label for="body">Your note</label>
        <textarea id="body" name="body" required maxlength={8000}>{draft ?? note.body}</textarea>
        <div class="btns"><button class="btn btn-red" type="submit">Save the note</button><a class="btn" href={`/notes/${ref}`}>Leave it</a></div>
      </form>
    </>
  );
};

function stamp(iso: string): string {
  const d = new Date(iso);
  const M = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
  return `${String(d.getUTCDate()).padStart(2, "0")}-${M[d.getUTCMonth()]}-${d.getUTCFullYear()} ${String(d.getUTCHours()).padStart(2, "0")}:${String(d.getUTCMinutes()).padStart(2, "0")}`;
}

export { prettyDate };
