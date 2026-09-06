/** The topic page: one night, the setlist, the tapes, what the heads say, the notes. */
import type { FC } from "hono/jsx";
import type { CatalogRecording, CatalogShow, Digest, SetlistEntry, ShowImage } from "../catalog/queries";
import type { Track } from "../archive/files";
import type { Head } from "../env";
import { eraById, runsOn, notableShow, type FamousRun } from "../kb";
import { firstSentence, longDate, place, prettyDate, rating, showTitle, sourceBadge } from "../fmt";
import { Empty, NoteBlock, Scans, Setlist, SpinLink, TapesTable } from "./parts";

export interface NoteView {
  ref: string; handle: string | null; body: string; created_at: string; deleted_by: string | null;
}

export interface ShowPageProps {
  show: CatalogShow;
  entries: SetlistEntry[];
  matched: (number | null)[];
  tapes: CatalogRecording[];
  best: CatalogRecording | null;
  bestTracks: Track[];
  digest: Digest | null;
  images: ShowImage[];
  topic: { id: number; note_count: number } | null;
  notes: NoteView[];
  runs: { run: FamousRun; from: number; to: number }[];
  head: Head | null;
  shelves: { id: string; name: string }[];
  prev: CatalogShow | null;
  next: CatalogShow | null;
  error?: string | null;
  draft?: string;
  ok?: string | null;
}

export const ShowTopic: FC<ShowPageProps> = (p) => {
  const era = eraById(p.show.era_id);
  const kb = notableShow(p.show.date);
  const standouts = p.digest ? safeList(p.digest.standout_songs_json) : [];
  return (
    <>
      <h1 class="topic">{showTitle(p.show)}{p.show.show_id.endsWith("-early") ? " · early show" : p.show.show_id.endsWith("-late") ? " · late show" : ""}</h1>
      <p class="meta">
        {longDate(p.show.date)}
        {era ? <> · <a href={`/years#${era.id}`}>{era.name}</a></> : null}
        {p.topic ? <> · Topic {p.topic.id} · {p.topic.note_count} {p.topic.note_count === 1 ? "note" : "notes"}</> : <> · No notes yet</>}
        {" · "}<a href={`/shows/${p.show.show_id}.txt`}>setlist.txt</a>
        {" · "}<a href={`https://archive.org/search?query=collection%3AGratefulDead+date%3A${p.show.date}`}>archive.org</a>
      </p>
      {kb ? <p class="sub">{kb.blurb}</p> : null}
      {p.ok ? <p class="ok">{p.ok}</p> : null}

      <div class="btns">
        {p.best ? <SpinLink identifier={p.best.identifier} label="Spin the best tape" /> : null}
        {p.best ? <span class="help">{sourceBadge(p.best.source_type)}{p.best.taper ? ` · ${p.best.taper}` : ""} · {rating(p.best.avg_rating)}</span> : null}
        {p.runs.map(({ run, from, to }) => (
          <SpinLink identifier={p.best!.identifier} from={from} to={to} primary={false} label={`Play ${run.title}`} />
        ))}
        {p.head && p.best ? (
          <form method="post" action="/me/shelves/add" class="inline">
            <input type="hidden" name="show_id" value={p.show.show_id} />
            <label class="vh" for="shelf">Shelf</label>
            <select id="shelf" name="shelf_id">
              {p.shelves.map((s) => <option value={s.id}>{s.name}</option>)}
              <option value="new">A new shelf…</option>
            </select>
            <button class="btn" type="submit">Shelve it</button>
          </form>
        ) : null}
        {p.head ? <a class="btn" href={`/me/journal?show=${p.show.show_id}`}>Log it in the journal</a> : null}
      </div>

      <h2>Setlist</h2>
      {p.show.setlist_status === "partial" ? <p class="help">Setlist's partial. If you were there, write a note.</p> : null}
      <Setlist entries={p.entries} identifier={p.best?.identifier ?? null} matched={p.matched} tracks={p.bestTracks} />

      <h2>Tapes</h2>
      <TapesTable show={p.show} tapes={p.tapes} best={p.best?.identifier} />

      <h2>What the Heads Say</h2>
      {p.digest ? (
        <div class="digest">
          <p class="rating">Heads rate this one {p.digest.derived_rating.toFixed(1)} · archive.org says {rating(p.show.avg_rating)} over {p.show.total_reviews} reviews</p>
          <p>{p.digest.consensus_summary}</p>
          {standouts.length ? <p class="meta">Standouts: {standouts.join(" · ")}</p> : null}
          {p.digest.rating_rationale ? <details><summary>Why {p.digest.derived_rating.toFixed(1)}</summary><p>{p.digest.rating_rationale}</p></details> : null}
        </div>
      ) : <Empty>No digest for this night yet. The reviews are on the tape pages.</Empty>}

      {p.images.length ? (<><h2>Tickets and Posters</h2><Scans images={p.images} /></>) : null}

      <h2 id="notes">Notes</h2>
      {p.notes.length ? p.notes.map((n) => (
        <NoteBlock handle={n.handle} ref={n.ref} href={`/notes/${n.ref}`} stamp={n.created_at} body={n.body} deleted={n.deleted_by} />
      )) : <Empty>No notes on this show yet. You know something about this night. Write it down.</Empty>}

      <h2 id="write">Write a Note</h2>
      {p.head ? (
        <form method="post" action={`/shows/${p.show.show_id}/notes`}>
          {p.error ? <p class="err" role="alert">{p.error}</p> : null}
          <label for="body">Your note</label>
          <textarea id="body" name="body" required maxlength={8000} aria-describedby="body-help">{p.draft ?? ""}</textarea>
          <p class="help" id="body-help">Plain text. A {">"} stays a segue; 5/8/77 and NODE::NAME turn into links. Say which tape you spun.</p>
          <div class="btns"><button class="btn btn-red" type="submit">Post the note</button></div>
        </form>
      ) : <p class="help">Notes need a handle. <a href="/signin" data-full>Sign in</a> or <a href="/bus" data-full>get on the bus</a>.</p>}

      <p class="meta nav2">
        {p.prev ? <a href={`/shows/${p.prev.show_id}`}>← {prettyDate(p.prev.date)} {p.prev.venue ?? place(p.prev)}</a> : null}
        {p.prev && p.next ? " · " : ""}
        {p.next ? <a href={`/shows/${p.next.show_id}`}>{prettyDate(p.next.date)} {p.next.venue ?? place(p.next)} →</a> : null}
      </p>
    </>
  );
};

export function safeList(json: string): string[] {
  try {
    const v = JSON.parse(json);
    return Array.isArray(v) ? v.map(String) : [];
  } catch {
    return [];
  }
}

export { firstSentence, runsOn };
