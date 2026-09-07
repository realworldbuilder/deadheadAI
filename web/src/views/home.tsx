/** The front page: tonight's show, on this day, recent notes, the lot. */
import type { FC } from "hono/jsx";
import type { CatalogShow, CatalogRecording } from "../catalog/queries";
import type { Head } from "../env";
import type { FamousRun } from "../kb";
import { count, monthDay, prettyDate, rating, showTitle, sourceBadge } from "../fmt";
import { Empty, NoteBlock, SpinLink } from "./parts";
import type { NoteView } from "./show";
import { words } from "./lists";

export interface HomeProps {
  head: Head | null;
  tonight: { show: CatalogShow; best: CatalogRecording | null; blurb: string | null; runs: { run: FamousRun; from: number; to: number }[] } | null;
  otd: { month: number; day: number; shows: CatalogShow[]; nearest: CatalogShow[] };
  notes: (NoteView & { show_id: string; show_label: string })[];
  lot: { handle: string; show_id: string | null; identifier: string; track_title: string; date: string | null }[];
  counts: { shows: string; tapes: string; notes: number; heads: number };
  quote: { text: string; attribution: string };
}

export const Home: FC<HomeProps> = (p) => {
  const y = p.otd.shows.map((s) => s.year);
  return (
    <>
      <h1 class="mark">RDVAX::GRATEFUL</h1>
      <p class="sub">The Dead conference, back up. Every show is a topic. Write a note.</p>
      {p.head ? null : (
        <div class="btns">
          <a class="btn btn-red" href="/bus" data-full>Get on the Bus</a>
          <a class="btn" href="/signin" data-full>Sign in</a>
          <span class="help">Handles look like NACAD2::SIEGEL. No email. Face ID or Touch ID instead of a password.</span>
        </div>
      )}

      <h2>Tonight's Show</h2>
      {p.tonight ? (
        <div class="card">
          <p class="topic"><a href={`/shows/${p.tonight.show.show_id}`}>{showTitle(p.tonight.show)}</a></p>
          {p.tonight.blurb ? <p>{p.tonight.blurb}</p> : null}
          {p.tonight.best ? <p class="rating">{sourceBadge(p.tonight.best.source_type)} · {rating(p.tonight.best.avg_rating)} · {p.tonight.best.num_reviews} reviews{p.tonight.best.taper ? ` · ${p.tonight.best.taper}` : ""}</p> : null}
          <div class="btns">
            {p.tonight.best ? <SpinLink identifier={p.tonight.best.identifier} label="Spin the best tape" /> : null}
            <a class="btn" href={`/shows/${p.tonight.show.show_id}`}>Read the topic</a>
            {p.tonight.runs.map(({ run, from, to }) => <SpinLink identifier={p.tonight!.best!.identifier} from={from} to={to} primary={false} label={`Play ${run.title}`} />)}
          </div>
        </div>
      ) : <Empty>Nothing cued for tonight. Pick a year.</Empty>}

      <h2>On This Day</h2>
      {p.otd.shows.length ? (
        <p>The boys played {monthDay(p.otd.month, p.otd.day)} {words(p.otd.shows.length)} {p.otd.shows.length === 1 ? "time" : "times"}{y.length > 1 ? `, '${String(y[0]! % 100).padStart(2, "0")} to '${String(y[y.length - 1]! % 100).padStart(2, "0")}` : ""}. <a href="/on-this-day">See them all</a></p>
      ) : (
        <p>No show on {monthDay(p.otd.month, p.otd.day)}. Nearest is {p.otd.nearest.map((s, i) => <>{i ? ", " : ""}<a href={`/shows/${s.show_id}`}>{prettyDate(s.date)} {s.venue ?? ""}</a></>)}.</p>
      )}

      <h2>Recent Notes</h2>
      {p.notes.length ? p.notes.map((n) => (
        <NoteBlock mini handle={n.handle} ref={n.ref} href={`/notes/${n.ref}`} stamp={n.created_at} body={n.body} deleted={n.deleted_by} showLink={{ href: `/shows/${n.show_id}`, label: n.show_label }} />
      )) : <Empty>Nobody's written a note yet. Open any show and be the first.</Empty>}
      {p.notes.length ? <p class="meta"><a href="/notes">All the notes →</a></p> : null}

      <h2>The Lot</h2>
      {p.lot.length ? (
        <ol class="rows">
          {p.lot.map((s) => (
            <li>
              <a href={`/heads/${s.handle}`}>{s.handle}</a> · {s.show_id ? <a href={`/shows/${s.show_id}`}>{prettyDate(s.date ?? s.show_id)}</a> : s.identifier} · {s.track_title}
              {" · "}<a href={`https://archive.org/details/${s.identifier}`} data-spin={s.identifier}>Spin along</a>
            </li>
          ))}
        </ol>
      ) : <Empty>The lot's empty. Spin a tape and you'll be in it.</Empty>}
      <p class="meta"><a href="/lot">Everyone in the lot →</a></p>

      <blockquote class="quote"><p>“{p.quote.text}”</p><footer class="meta">— {p.quote.attribution}</footer></blockquote>
      <p class="meta">{p.counts.shows} shows · {p.counts.tapes} tapes · {count(p.counts.notes)} notes · {count(p.counts.heads)} heads</p>
    </>
  );
};
