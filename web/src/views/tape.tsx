/** One tape: its tracks laid out by the setlist, the reviews, the other tapes. */
import type { FC } from "hono/jsx";
import type { CatalogRecording, CatalogShow } from "../catalog/queries";
import type { Row } from "../catalog/setlist";
import type { Track } from "../archive/files";
import { detailsUrl, totalSeconds } from "../archive/files";
import type { Head } from "../env";
import { mins, prettyDate, rating, showTitle, sourceBadge, stampDate } from "../fmt";
import { Empty, Err, NoteBlock, SpinLink, TapesTable, TrackList } from "./parts";

export interface Review { title: string | null; body: string | null; stars: number | null; reviewer: string | null; date: string | null }

export interface TapePageProps {
  show: CatalogShow;
  tape: CatalogRecording;
  tracks: Track[];
  rows: Row[];
  fromCatalog: boolean;
  reviews: Review[] | null;
  others: CatalogRecording[];
  head: Head | null;
  mixtapes: { id: string; name: string }[];
}

export const TapePage: FC<TapePageProps> = (p) => (
  <>
    <h1 class="topic">{showTitle(p.show)}</h1>
    <p class="meta">{p.tape.identifier}</p>
    <p class="rating">
      <span class="src">{sourceBadge(p.tape.source_type)}</span> · {rating(p.tape.avg_rating)} ★ · {p.tape.num_reviews} reviews · {p.tape.downloads.toLocaleString("en-US")} downloads
      {p.tape.taper ? <> · {p.tape.taper}</> : null}
    </p>
    {p.tape.source_text ? <dl class="meta"><dt>Source</dt><dd>{p.tape.source_text}</dd>{p.tape.lineage ? <><dt>Lineage</dt><dd>{p.tape.lineage}</dd></> : null}</dl> : null}

    <div class="btns">
      {p.tracks.length ? <SpinLink identifier={p.tape.identifier} /> : null}
      <a class="btn" href={detailsUrl(p.tape.identifier)}>On archive.org</a>
      <a class="btn" href={`/shows/${p.show.show_id}`}>The topic</a>
      {p.head && p.tracks.length ? (
        <form method="post" action="/me/mixtapes/add" class="inline">
          <input type="hidden" name="identifier" value={p.tape.identifier} />
          <label class="vh" for="track">Tune</label>
          <select id="track" name="file_name">
            {p.tracks.map((t) => <option value={t.fileName}>{t.title}</option>)}
          </select>
          <label class="vh" for="mixtape">Mix tape</label>
          <select id="mixtape" name="mixtape_id">
            {p.mixtapes.map((m) => <option value={m.id}>{m.name}</option>)}
            <option value="new">A new mix tape…</option>
          </select>
          <button class="btn" type="submit">Put it on a mix tape</button>
        </form>
      ) : null}
    </div>

    <h2>Tracks</h2>
    {p.tracks.length ? (
      <>
        <TrackList rows={p.rows} tracks={p.tracks} identifier={p.tape.identifier} />
        <p class="meta">{p.tracks.length} tracks · {mins(totalSeconds(p.tracks))}{p.fromCatalog ? "" : " · pulled from archive.org"}</p>
      </>
    ) : <Empty>Track list isn't in the catalog for this one and archive.org didn't answer. Try it <a href={detailsUrl(p.tape.identifier)}>over there</a>.</Empty>}

    <h2>Show Reviews</h2>
    {p.reviews === null ? <Err>archive.org didn't answer, so no reviews right now.</Err>
      : p.reviews.length === 0 ? <Empty>No reviews on this tape yet.</Empty>
      : p.reviews.map((r, i) => (
        <NoteBlock
          handle={`archive.org · ${r.reviewer ?? "someone"}`}
          ref={r.stars != null ? "★".repeat(Math.max(0, Math.min(5, Math.round(r.stars)))) : "review"}
          stamp={r.date ?? ""}
          body={(r.title ? r.title + "\n\n" : "") + (r.body ?? "")}
        />
      ))}

    <h2>Other Tapes</h2>
    {p.others.length ? <TapesTable show={p.show} tapes={p.others} best={p.show.best_identifier} /> : <Empty>This is the only tape of the night.</Empty>}
  </>
);

export { prettyDate, stampDate };
