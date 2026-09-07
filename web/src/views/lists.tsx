/** Years, one year, on this day, the nights heads name, search, the songs. */
import type { FC } from "hono/jsx";
import type { CatalogShow, CatalogSong, YearCount } from "../catalog/queries";
import { eras, notableShows, songInfo, type Era, type NotableShow } from "../kb";
import { count, longDate, monthDay, prettyDate, songSlug } from "../fmt";
import { Empty, ShowRows } from "./parts";

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

export const Years: FC<{ counts: YearCount[] }> = ({ counts }) => (
  <>
    <h1>Years</h1>
    <p class="sub">Thirty years, and a different band every few of them.</p>
    {eras.map((era: Era) => {
      const rows = counts.filter((c) => c.year >= era.startYear && c.year <= era.endYear);
      return (
        <section id={era.id}>
          <h2>{era.name} · {era.years}</h2>
          <p>{era.style}</p>
          <ol class="rows">
            {rows.map((c) => (
              <li><a class="d" href={`/years/${c.year}`}>{c.year}</a> · {c.show_count} {c.show_count === 1 ? "show" : "shows"} · {count(c.recording_count)} tapes</li>
            ))}
          </ol>
        </section>
      );
    })}
  </>
);

export const Year: FC<{ year: number; shows: CatalogShow[]; era: Era | null; notes: Map<string, number>; tapes: number }> = ({ year, shows, era, notes, tapes }) => {
  const months = new Map<number, CatalogShow[]>();
  for (const s of shows) {
    const list = months.get(s.month) ?? [];
    list.push(s);
    months.set(s.month, list);
  }
  return (
    <>
      <h1>{year}</h1>
      <p class="sub">{era ? `${era.name} · ` : ""}{shows.length} shows · {count(tapes)} tapes</p>
      <p class="meta">{[...months.keys()].map((m) => <><a href={`#m${m}`}>{MONTHS[m - 1]!.slice(0, 3)}</a> </>)}</p>
      {[...months.entries()].map(([m, list]) => (
        <section id={`m${m}`}>
          <h2>{MONTHS[m - 1]}</h2>
          <ShowRows shows={list} notes={notes} />
        </section>
      ))}
      <p class="meta nav2">
        {year > 1965 ? <a href={`/years/${year - 1}`}>← {year - 1}</a> : null}
        {year > 1965 && year < 1995 ? " · " : ""}
        {year < 1995 ? <a href={`/years/${year + 1}`}>{year + 1} →</a> : null}
      </p>
    </>
  );
};

export const OnThisDay: FC<{ month: number; day: number; shows: CatalogShow[]; nearest: CatalogShow[]; notes: Map<string, number> }> = ({ month, day, shows, nearest, notes }) => {
  const years = shows.map((s) => s.year);
  const span = years.length ? `'${String(years[0]! % 100).padStart(2, "0")} to '${String(years[years.length - 1]! % 100).padStart(2, "0")}` : "";
  return (
    <>
      <h1>On This Day</h1>
      <p class="sub">{monthDay(month, day)} · {shows.length ? `${words(shows.length)} ${shows.length === 1 ? "night" : "nights"}, ${span}` : "nothing on the books"}</p>
      {shows.length ? <ShowRows shows={shows} notes={notes} /> : (
        <>
          <Empty>No show on {monthDay(month, day)}. Nearest nights:</Empty>
          <ShowRows shows={nearest} />
        </>
      )}
      <p class="meta nav2"><a href={`/on-this-day?d=${shift(month, day, -1)}`}>← yesterday</a> · <a href={`/on-this-day?d=${shift(month, day, 1)}`}>tomorrow →</a></p>
    </>
  );
};

function shift(month: number, day: number, by: number): string {
  const d = new Date(Date.UTC(1977, month - 1, day + by));
  return `${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`;
}

const WORDS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"];
export function words(n: number): string {
  return WORDS[n] ?? String(n);
}

export const NotableIndex: FC<{ byDate: Map<string, CatalogShow> }> = ({ byDate }) => {
  const byEra = new Map<string, NotableShow[]>();
  for (const n of notableShows) {
    const list = byEra.get(n.eraID) ?? [];
    list.push(n);
    byEra.set(n.eraID, list);
  }
  return (
    <>
      <h1>Shows</h1>
      <p class="sub">The nights heads name first. Every one of them is a topic; the rest are under <a href="/years">the years</a>.</p>
      {eras.map((era) => {
        const list = (byEra.get(era.id) ?? []).sort((a, b) => a.date.localeCompare(b.date));
        if (!list.length) return null;
        return (
          <section>
            <h2>{era.name} · {era.years}</h2>
            <ol class="rows">
              {list.map((n) => {
                const s = byDate.get(n.date);
                return (
                  <li>
                    <a class="d" href={s ? `/shows/${s.show_id}` : `/shows/${n.date}`}>{prettyDate(n.date)}</a> · {n.venue} · {n.location}
                    <br /><span class="blurb">{n.blurb}</span>
                  </li>
                );
              })}
            </ol>
          </section>
        );
      })}
    </>
  );
};

export interface SearchProps {
  q: string;
  shows: CatalogShow[];
  hit: { kind: "show"; show: CatalogShow } | { kind: "noshow"; date: string; nearest: CatalogShow[] } | { kind: "song"; song: CatalogSong } | null;
  notes: Map<string, number>;
}

export const Search: FC<SearchProps> = ({ q, shows, hit, notes }) => (
  <>
    <h1>Search</h1>
    <form method="get" action="/search" role="search">
      <label for="q">What are you looking for</label>
      <input id="q" type="search" name="q" value={q} aria-describedby="q-help" autofocus={!q} />
      <p class="help" id="q-help">A date like 5-8-77, a venue, a tune, a year. Dark Star 1972. Hot Scarlet Fire.</p>
      <div class="btns"><button class="btn btn-red" type="submit">Search</button></div>
    </form>
    {hit?.kind === "show" ? <p class="hit">Direct hit: <a href={`/shows/${hit.show.show_id}`}>{prettyDate(hit.show.date)} · {hit.show.venue ?? ""}</a></p> : null}
    {hit?.kind === "noshow" ? <p class="hit">No show on {prettyDate(hit.date)}. Nearest: {hit.nearest.map((s, i) => <>{i ? " · " : ""}<a href={`/shows/${s.show_id}`}>{prettyDate(s.date)} {s.venue ?? ""}</a></>)}</p> : null}
    {hit?.kind === "song" ? <p class="hit">Tune: <a href={`/songs/${songSlug(hit.song.song_key)}`}>{hit.song.title}</a> · {hit.song.times_played} times</p> : null}
    {q ? (
      <>
        <h2>Shows</h2>
        {shows.length ? <><p class="meta">{shows.length === 50 ? "First 50" : shows.length} shows for “{q}”</p><ShowRows shows={shows} notes={notes} /></>
          : <Empty>Nothing for “{q}”. Try a date like 5-8-77, a venue, or a tune.</Empty>}
      </>
    ) : null}
  </>
);

export const Songs: FC<{ songs: CatalogSong[]; q: string }> = ({ songs, q }) => (
  <>
    <h1>Songs</h1>
    <p class="sub">Every tune in the setlists, most played first.</p>
    <form method="get" action="/songs">
      <label for="q">Find a song</label>
      <input id="q" type="search" name="q" value={q} />
    </form>
    <ol class="rows">
      {songs.map((s) => <li><a href={`/songs/${songSlug(s.song_key)}`}>{s.title}</a> · {s.times_played} {s.times_played === 1 ? "play" : "plays"}{s.first_played ? <> · {prettyDate(s.first_played)}–{prettyDate(s.last_played ?? s.first_played)}</> : null}</li>)}
    </ol>
  </>
);

export const Song: FC<{ song: CatalogSong; shows: (CatalogShow & { segues_into_next: number })[]; into: { song_key: string; song_title: string; n: number }[] }> = ({ song, shows, into }) => {
  const info = songInfo(song.song_key);
  const byYear = new Map<number, CatalogShow[]>();
  for (const s of shows) {
    const list = byYear.get(s.year) ?? [];
    list.push(s);
    byYear.set(s.year, list);
  }
  return (
    <>
      <h1>{song.title}</h1>
      <p class="sub">
        {info?.writtenBy ? `${info.writtenBy} · ` : ""}
        {song.first_played ? `first ${prettyDate(song.first_played)} · ` : ""}
        {song.last_played ? `last ${prettyDate(song.last_played)} · ` : ""}
        {song.times_played} times
      </p>
      {info?.evolution ? <p>{info.evolution}</p> : null}
      {info?.famousVersions?.length ? (
        <>
          <h2>Favorite Versions</h2>
          <ol class="rows">
            {info.famousVersions.map((v) => <li><a class="d" href={`/shows/${v.date}`}>{prettyDate(v.date)}</a> · {v.label}<br /><span class="blurb">{v.note}</span></li>)}
          </ol>
        </>
      ) : null}
      {into.length ? (
        <>
          <h2>Goes Into</h2>
          <ol class="rows">
            {into.map((i) => <li>{song.title} <span class="segue">{">"}</span> <a href={`/songs/${songSlug(i.song_key)}`}>{i.song_title}</a> · {i.n} {i.n === 1 ? "time" : "times"}</li>)}
          </ol>
        </>
      ) : null}
      <h2>Every Version</h2>
      {shows.length === 0 ? <Empty>No setlist has it. The catalog only knows what got typed in.</Empty> : null}
      {[...byYear.entries()].map(([year, list]) => (
        <details open={byYear.size <= 3}>
          <summary>{year} · {list.length} {list.length === 1 ? "version" : "versions"}</summary>
          <ShowRows shows={list} />
        </details>
      ))}
    </>
  );
};

export { longDate };
