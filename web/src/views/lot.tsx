/** The lot: who's spinning what right now. */
import type { FC } from "hono/jsx";
import { prettyDate } from "../fmt";
import { Empty } from "./parts";

export interface SpinRow { handle: string; show_id: string | null; identifier: string; track_title: string; updated_at: string }

function ago(iso: string): string {
  const m = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 60000));
  return m === 0 ? "just now" : m === 1 ? "a minute ago" : m < 60 ? `${m} min ago` : `${Math.round(m / 60)} h ago`;
}

export const Lot: FC<{ now: SpinRow[]; earlier: SpinRow[] }> = ({ now, earlier }) => (
  <>
    <h1>The Lot</h1>
    <p class="sub">Who's spinning what right now.</p>
    {now.length === 0 ? <Empty>The lot's empty right now. Spin a tape and you'll be in it.</Empty> : (
      <ol class="rows">
        {now.map((s) => (
          <li>
            <a href={`/heads/${s.handle}`}>{s.handle}</a> · {s.show_id ? <a href={`/shows/${s.show_id}`}>{prettyDate(s.show_id)}</a> : s.identifier} · {s.track_title} · <span class="meta">{ago(s.updated_at)}</span>
            {" · "}<a href={`https://archive.org/details/${s.identifier}`} data-spin={s.identifier}>Spin along</a>
          </li>
        ))}
      </ol>
    )}
    {earlier.length ? (
      <>
        <h2>Earlier Tonight</h2>
        <ol class="rows">
          {earlier.map((s) => <li><a href={`/heads/${s.handle}`}>{s.handle}</a> · {s.show_id ? <a href={`/shows/${s.show_id}`}>{prettyDate(s.show_id)}</a> : s.identifier} · {s.track_title} · <span class="meta">{ago(s.updated_at)}</span></li>)}
        </ol>
      </>
    ) : null}
    <p class="help">Don't want to be seen? Turn off “Show me in the lot” on <a href="/me">your page</a>.</p>
  </>
);
