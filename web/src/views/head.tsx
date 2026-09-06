/** A head's page: the bus line, the tape list, the trees, the notes. */
import type { FC } from "hono/jsx";
import type { Head } from "../env";
import { mins, noteNumber, prettyDate } from "../fmt";
import { Empty, NoteBlock } from "./parts";
import { showLabel, type NoteRow } from "./notes";

export interface HeadProfile { id: string; handle: string; first_show: string | null; created_at: string }
export interface ShelfSummary { id: string; name: string; blurb: string; n: number; is_private: number }
export interface MixtapeSummary { id: string; name: string; blurb: string; n: number; seconds: number; is_private: number }
export interface TreeSummary { id: string; kind: string; name: string; owner: string; members: number }
export interface SpinNow { show_id: string | null; identifier: string; track_title: string }

export function busLine(firstShow: string | null): string | null {
  if (!firstShow) return null;
  return firstShow.length === 4 ? `On the bus since '${firstShow.slice(2)}` : `On the bus since ${prettyDate(firstShow)}`;
}

export const HeadPage: FC<{ profile: HeadProfile; viewer: Head | null; noteCount: number; notes: NoteRow[]; shelves: ShelfSummary[]; mixtapes: MixtapeSummary[]; trees: TreeSummary[]; spinning: SpinNow | null }> =
  ({ profile, viewer, noteCount, notes, shelves, mixtapes, trees, spinning }) => {
    const bus = busLine(profile.first_show);
    const mine = viewer?.id === profile.id;
    return (
      <>
        <h1 class="topic">{profile.handle}</h1>
        <p class="sub">
          {bus ? bus + " · " : ""}{noteCount} {noteCount === 1 ? "note" : "notes"} · {shelves.length} {shelves.length === 1 ? "shelf" : "shelves"} · {mixtapes.length} mix {mixtapes.length === 1 ? "tape" : "tapes"}
          {mine ? <> · <a href="/me">your page</a></> : null}
        </p>
        {spinning ? (
          <p class="rating">Spinning {spinning.show_id ? <a href={`/shows/${spinning.show_id}`}>{prettyDate(spinning.show_id)}</a> : spinning.identifier} · {spinning.track_title} · <a href={`https://archive.org/details/${spinning.identifier}`} data-spin={spinning.identifier}>Spin along</a></p>
        ) : null}

        <h2>Tape List</h2>
        {shelves.length + mixtapes.length === 0 ? <Empty>No tapes on the shelf yet.</Empty> : (
          <>
            <p class="meta"><a href={`/heads/${profile.handle}.txt`}>tape list .txt</a></p>
            <ol class="rows">
              {shelves.map((s) => <li><a href={`/heads/${profile.handle}/shelves/${s.id}`}>{s.name}</a> · {s.n} {s.n === 1 ? "tape" : "tapes"}{s.is_private ? " · private" : ""}</li>)}
              {mixtapes.map((m) => <li><a href={`/heads/${profile.handle}/mixtapes/${m.id}`}>{m.name}</a> · mix tape · {m.n} {m.n === 1 ? "tune" : "tunes"}{m.seconds ? ` · ${mins(m.seconds)}` : ""}{m.is_private ? " · private" : ""}{m.n ? <> · <a href={`/heads/${profile.handle}/mixtapes/${m.id}`} data-mix={m.id}>Spin</a></> : null}</li>)}
            </ol>
          </>
        )}

        <h2>Trees</h2>
        {trees.length === 0 ? <Empty>Not on any trees.</Empty> : (
          <ol class="rows">
            {trees.map((t) => <li><a href={`/trees/${t.id}`}>{t.name}</a> · {t.kind === "shelf" ? "a shelf" : "a mix tape"} · {t.members} {t.members === 1 ? "head" : "heads"} · started by <a href={`/heads/${t.owner}`}>{t.owner}</a></li>)}
          </ol>
        )}

        <h2>Notes</h2>
        {notes.length === 0 ? <Empty>No notes from {profile.handle} yet.</Empty> : notes.map((n) => (
          <NoteBlock mini handle={n.handle} ref={noteNumber(n.topic_id, n.reply_no)} href={`/notes/${noteNumber(n.topic_id, n.reply_no)}`} stamp={n.created_at}
            body={n.body.length > 160 ? n.body.slice(0, 159).trimEnd() + "…" : n.body} deleted={n.deleted_by} showLink={{ href: `/shows/${n.show_id}`, label: showLabel(n.title) }} />
        ))}
        {noteCount > notes.length ? <p class="meta"><a href={`/heads/${profile.handle}/notes`}>All {noteCount} notes →</a></p> : null}
      </>
    );
  };

export const HeadNotes: FC<{ profile: HeadProfile; notes: NoteRow[]; older: number | null }> = ({ profile, notes, older }) => (
  <>
    <h1 class="topic">{profile.handle} · notes</h1>
    {notes.length === 0 ? <Empty>No notes from {profile.handle} yet.</Empty> : notes.map((n) => (
      <NoteBlock handle={n.handle} ref={noteNumber(n.topic_id, n.reply_no)} href={`/notes/${noteNumber(n.topic_id, n.reply_no)}`} stamp={n.created_at}
        body={n.body} deleted={n.deleted_by} showLink={{ href: `/shows/${n.show_id}`, label: showLabel(n.title) }} />
    ))}
    {older ? <p class="meta"><a href={`/heads/${profile.handle}/notes?before=${older}`}>Older notes →</a></p> : null}
    <p class="meta"><a href={`/heads/${profile.handle}`}>← {profile.handle}</a></p>
  </>
);
