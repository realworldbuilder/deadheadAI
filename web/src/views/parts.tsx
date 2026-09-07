/** Reusable bits: show rows, the tapes table, setlist rows, notes, empties, errors. */
import type { Child, FC } from "hono/jsx";
import type { CatalogRecording, CatalogShow, SetlistEntry } from "../catalog/queries";
import type { Track } from "../archive/files";
import { detailsUrl, stripLeadingTrackNumber, streamUrl } from "../archive/files";
import type { Row } from "../catalog/setlist";
import { mmss, noteStamp, place, prettyDate, rating, songSlug, sourceBadge } from "../fmt";
import { NoteBody } from "./notes";

export const ShowRow: FC<{ show: CatalogShow; extra?: Child; noteCount?: number }> = ({ show, extra, noteCount }) => (
  <li>
    <a class="d" href={`/shows/${show.show_id}`}>{prettyDate(show.date)}</a>
    {show.show_id.endsWith("-early") ? " (early)" : show.show_id.endsWith("-late") ? " (late)" : ""}
    {show.venue ? <> · {show.venue}</> : null}
    {place(show) ? <> · {place(show)}</> : null}
    {show.best_source_type ? <> · <span class="src">{sourceBadge(show.best_source_type)}</span></> : null}
    {show.avg_rating != null ? <> {rating(show.avg_rating)}</> : null}
    {noteCount ? <> · {noteCount} {noteCount === 1 ? "note" : "notes"}</> : null}
    {extra}
  </li>
);

export const ShowRows: FC<{ shows: CatalogShow[]; notes?: Map<string, number> }> = ({ shows, notes }) => (
  <ol class="rows">
    {shows.map((s) => <ShowRow show={s} noteCount={notes?.get(s.show_id)} />)}
  </ol>
);

export const Stars: FC<{ n: number | null }> = ({ n }) => {
  if (n == null) return <span class="meta">unrated</span>;
  const full = Math.round(n);
  return <span class="rating" aria-label={`${n} out of 5`}>{"★".repeat(full)}{"☆".repeat(5 - full)}</span>;
};

export const TapesTable: FC<{ show: CatalogShow; tapes: CatalogRecording[]; best?: string | null; open?: number }> = ({ show, tapes, best, open = 8 }) => {
  if (tapes.length === 0) return <p class="empty">No tape of this night on archive.org.</p>;
  const row = (t: CatalogRecording) => (
    <tr class={t.identifier === best ? "best" : undefined}>
      <td class="src" title={t.identifier === best ? "The one to spin" : undefined}>{t.identifier === best ? "◆ " : ""}{sourceBadge(t.source_type)}</td>
      <td>{rating(t.avg_rating)}</td>
      <td>{t.num_reviews}</td>
      <td>{t.taper ?? ""}</td>
      <td><a href={`/shows/${show.show_id}/${t.identifier}`}>{t.identifier}</a></td>
    </tr>
  );
  const head = tapes.slice(0, open);
  const rest = tapes.slice(open);
  return (
    <div class="scroll">
      <table class="tapes">
        <thead><tr><th>Source</th><th>Rating</th><th>Reviews</th><th>Taper</th><th>Tape</th></tr></thead>
        <tbody>{head.map(row)}</tbody>
      </table>
      {rest.length > 0 ? (
        <details>
          <summary>All {tapes.length} tapes</summary>
          <table class="tapes"><tbody>{rest.map(row)}</tbody></table>
        </details>
      ) : null}
    </div>
  );
};

/** The setlist as typed, with a ▶ where the tape carries the tune. */
export const Setlist: FC<{ entries: SetlistEntry[]; identifier: string | null; matched: (number | null)[]; tracks: Track[] }> = ({ entries, identifier, matched, tracks }) => {
  if (entries.length === 0) return <p class="empty">No setlist typed in for this one yet.</p>;
  const groups: { label: string; items: { e: SetlistEntry; idx: number | null }[] }[] = [];
  entries.forEach((e, n) => {
    const last = groups[groups.length - 1];
    const item = { e, idx: matched[n] ?? null };
    if (last && last.label === e.set_label) last.items.push(item);
    else groups.push({ label: e.set_label, items: [item] });
  });
  return (
    <section class="setlist" data-spin={identifier ?? undefined}>
      {groups.map((g) => (
        <>
          <h3>{g.label}</h3>
          <ol>
            {g.items.map(({ e, idx }) => {
              const track = idx != null ? tracks[idx] : undefined;
              return (
                <li class={track ? undefined : "off"} data-track={idx ?? undefined} title={track ? undefined : "Not on this tape"}>
                  {track && identifier
                    ? <a class="pl" href={streamUrl(identifier, track.fileName)} data-spin={identifier} data-from={idx!} aria-label={`Play ${e.song_title}`}>▶</a>
                    : <span class="pl" aria-hidden="true"> </span>}
                  <a href={`/songs/${songSlug(e.song_key)}`}>{e.song_title}</a>
                  {e.segues_into_next ? <span class="segue" aria-label="segues into"> {">"}</span> : null}
                  {track?.seconds ? <span class="dur">{mmss(track.seconds)}</span> : null}
                </li>
              );
            })}
          </ol>
        </>
      ))}
    </section>
  );
};

/** The tape's tracks as rows, shaped by the setlist (set headings, segue marks, dimmed missing songs). */
export const TrackList: FC<{ rows: Row[]; tracks: Track[]; identifier: string }> = ({ rows, tracks, identifier }) => (
  <ol class="setlist tracks" data-spin={identifier}>
    {rows.map((r) => {
      if (r.kind === "heading") return <li class="h"><h3>{r.label}</h3></li>;
      if (r.kind === "missing") {
        return <li class="off" title="Not on this tape"><span class="pl" aria-hidden="true"> </span><span class="n"></span>{r.entry.song_title}{r.entry.segues_into_next ? <span class="segue"> {">"}</span> : null}</li>;
      }
      const t = tracks[r.index]!;
      return (
        <li data-track={r.index}>
          <a class="pl" href={streamUrl(identifier, t.fileName)} data-spin={identifier} data-from={r.index} aria-label={`Play ${stripLeadingTrackNumber(t.title)}`}>▶</a>
          <span class="n">{String(r.index + 1).padStart(2, "0")}</span>
          {stripLeadingTrackNumber(t.title)}
          {r.segues ? <span class="segue" aria-label="segues into"> {">"}</span> : null}
          <span class="dur">{mmss(t.seconds)}</span>
        </li>
      );
    })}
  </ol>
);

export const SpinLink: FC<{ identifier: string; label?: string; from?: number; to?: number; primary?: boolean }> = ({ identifier, label = "Spin this tape", from, to, primary = true }) => (
  <a class={primary ? "btn btn-red" : "btn"} href={detailsUrl(identifier)} data-spin={identifier} data-from={from} data-to={to}>{label}</a>
);

export const NoteBlock: FC<{ handle: string | null; ref: string; href?: string; stamp: string; body: string; showLink?: { href: string; label: string }; deleted?: string | null; mini?: boolean }> =
  ({ handle, ref, href, stamp, body, showLink, deleted, mini }) => (
    <div class={mini ? "note mini" : "note"} id={mini ? undefined : `n${ref}`}>
      <div class="hdr">
        <b>{handle ? (handle.includes("::") ? <a href={`/heads/${handle}`}>{handle}</a> : handle) : "—"}</b> · GRATEFUL {href ? <a href={href}>{ref}</a> : ref}
        {showLink ? <> · <a href={showLink.href}>{showLink.label}</a></> : null}
        {" · "}{noteStamp(stamp)}
      </div>
      {deleted ? <p class="empty">{deleted === "admin" ? "Note pulled by the admin." : deleted === "erased" ? "This head left the bus; the note went with them." : "Note pulled by its author."}</p> : <NoteBody body={body} />}
    </div>
  );

export const Empty: FC<{ children?: Child }> = ({ children }) => <p class="empty">{children}</p>;
export const Err: FC<{ children?: Child }> = ({ children }) => <p class="err" role="alert">{children}</p>;
export const Ok: FC<{ children?: Child }> = ({ children }) => <p class="ok">{children}</p>;

export const Scans: FC<{ images: { kind: string; url: string; width: number | null; height: number | null }[] }> = ({ images }) => (
  <div class="scans">
    {images.map((im) => (
      <figure>
        <a href={im.url}><img src={im.url} alt={`${im.kind} scan`} loading="lazy" width={im.width ?? undefined} height={im.height ?? undefined} /></a>
        <figcaption>{im.kind[0]!.toUpperCase() + im.kind.slice(1)} · jerrygarcia.com</figcaption>
      </figure>
    ))}
  </div>
);
