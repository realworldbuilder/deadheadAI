/** Shelves, mix tapes and the journal: yours to edit, everyone's to read. */
import type { FC } from "hono/jsx";
import type { Head } from "../env";
import type { JournalEntry, Mixtape, MixtapeItem, Shelf, ShelfItem } from "../tapes/store";
import { mins, mmss, prettyDate } from "../fmt";
import { Empty, Err, Ok } from "./parts";

export interface TreeState { id: string; members: number; owner: string; joined: boolean } 

export const MeShelves: FC<{ head: Head; shelves: (Shelf & { n: number })[]; ok?: string | null; error?: string | null; show?: string | null }> = ({ head, shelves, ok, error, show }) => (
  <>
    <h1>Shelves</h1>
    <p class="sub">Where you keep your tapes. Public unless you say otherwise.</p>
    {ok ? <Ok>{ok}</Ok> : null}{error ? <Err>{error}</Err> : null}
    <form method="post" action="/me/shelves">
      {show ? <input type="hidden" name="show_id" value={show} /> : null}
      <label for="name">{show ? "A new shelf for it" : "New shelf"}</label>
      <input id="name" name="name" maxlength={60} required placeholder="Top Shelf" />
      <div class="btns"><button class="btn btn-red" type="submit">{show ? "Make the shelf and shelve it" : "Make a shelf"}</button></div>
    </form>
    {shelves.length === 0 ? <Empty>No shelves yet. Make one, then open any show and hit Shelve it.</Empty> : (
      <ol class="rows">
        {shelves.map((s) => <li><a href={`/me/shelves/${s.id}`}>{s.name}</a> · {s.n} {s.n === 1 ? "tape" : "tapes"}{s.is_private ? " · private" : ""} · <a href={`/heads/${head.handle}/shelves/${s.id}`}>view</a></li>)}
      </ol>
    )}
    <p class="meta"><a href="/me">← Your page</a></p>
  </>
);

export const MeShelf: FC<{ head: Head; shelf: Shelf; items: ShelfItem[]; tree: TreeState | null; ok?: string | null; error?: string | null }> = ({ head, shelf, items, tree, ok, error }) => (
  <>
    <h1>{shelf.name}</h1>
    <p class="sub">{items.length} {items.length === 1 ? "tape" : "tapes"}{shelf.is_private ? " · private" : ""} · <a href={`/heads/${head.handle}/shelves/${shelf.id}`}>how heads see it</a></p>
    {ok ? <Ok>{ok}</Ok> : null}{error ? <Err>{error}</Err> : null}
    <form method="post" action={`/me/shelves/${shelf.id}`}>
      <label for="name">Name</label>
      <input id="name" name="name" value={shelf.name} maxlength={60} required />
      <label for="blurb">A line about it</label>
      <input id="blurb" name="blurb" value={shelf.blurb} maxlength={300} />
      <label><input type="checkbox" name="is_private" value="1" checked={!!shelf.is_private} /> Keep it private</label>
      <div class="btns"><button class="btn btn-red" type="submit">Save</button></div>
    </form>
    <h2>Tapes</h2>
    {items.length === 0 ? <Empty>Nothing on it yet. Open any show and hit Shelve it.</Empty> : (
      <ol class="rows">
        {items.map((it, i) => (
          <li>
            <a class="d" href={it.show_id ? `/shows/${it.show_id}` : `https://archive.org/details/${it.show_identifier}`}>{it.show_date ? prettyDate(it.show_date) : it.show_identifier}</a> · {it.display_name.replace(/^\S+\s*/, "")}
            {" · "}<a href={`https://archive.org/details/${it.show_identifier}`} data-spin={it.show_identifier}>Spin</a>
            {" "}
            <form method="post" action={`/me/shelves/${shelf.id}/items/${it.id}/move`} class="inline">
              <button class="btn" name="dir" value="up" type="submit" disabled={i === 0} aria-label="Move up">↑</button>
              <button class="btn" name="dir" value="down" type="submit" disabled={i === items.length - 1} aria-label="Move down">↓</button>
            </form>{" "}
            <form method="post" action={`/me/shelves/${shelf.id}/items/${it.id}/delete`} class="inline"><button class="btn" type="submit">Take it off</button></form>
          </li>
        ))}
      </ol>
    )}
    <h2>Tree</h2>
    {shelf.is_private ? <p class="help">Private shelves can't be treed. Make it public first.</p>
      : tree ? <p>This shelf is a tree with {tree.members} {tree.members === 1 ? "head" : "heads"} on it. <a href={`/trees/${tree.id}`}>The tree</a></p>
      : <form method="post" action={`/me/shelves/${shelf.id}/tree`}><p class="help">A tree is a tape list that gets passed around. Start one and other heads can get on it.</p><div class="btns"><button class="btn" type="submit">Start a tree from this shelf</button></div></form>}
    <h2>Toss it</h2>
    <p class="help">The tapes stay on archive.org. Only the list goes.</p>
    <div class="btns"><a class="btn" href={`/me/shelves/${shelf.id}/toss`}>Toss the shelf</a></div>
    <p class="meta"><a href="/me/shelves">← Shelves</a></p>
  </>
);

export const MeMixtapes: FC<{ head: Head; mixtapes: (Mixtape & { n: number; seconds: number })[]; ok?: string | null; error?: string | null; pending?: { identifier: string; file: string } | null }> = ({ head, mixtapes, ok, error, pending }) => (
  <>
    <h1>Mix Tapes</h1>
    <p class="sub">Tunes off different tapes, in the order you want them. Two tunes that were a real segue play as one.</p>
    {ok ? <Ok>{ok}</Ok> : null}{error ? <Err>{error}</Err> : null}
    <form method="post" action="/me/mixtapes">
      {pending ? <><input type="hidden" name="identifier" value={pending.identifier} /><input type="hidden" name="file_name" value={pending.file} /></> : null}
      <label for="name">{pending ? "A new mix tape for it" : "New mix tape"}</label>
      <input id="name" name="name" maxlength={60} required placeholder="Sunday Morning" />
      <div class="btns"><button class="btn btn-red" type="submit">{pending ? "Make the mix tape and put it on" : "Make a mix tape"}</button></div>
    </form>
    {mixtapes.length === 0 ? <Empty>No mix tapes yet. Open any tape and put a tune on one.</Empty> : (
      <ol class="rows">
        {mixtapes.map((m) => <li><a href={`/me/mixtapes/${m.id}`}>{m.name}</a> · {m.n} {m.n === 1 ? "tune" : "tunes"}{m.seconds ? ` · ${mins(m.seconds)}` : ""}{m.is_private ? " · private" : ""}{m.n ? <> · <a href={`/heads/${head.handle}/mixtapes/${m.id}`} data-mix={m.id}>Spin</a></> : null}</li>)}
      </ol>
    )}
    <p class="meta"><a href="/me">← Your page</a></p>
  </>
);

export const MeMixtape: FC<{ head: Head; mixtape: Mixtape; items: MixtapeItem[]; tree: TreeState | null; ok?: string | null; error?: string | null }> = ({ head, mixtape, items, tree, ok, error }) => {
  const seconds = items.reduce((n, i) => n + (i.duration_seconds || 0), 0);
  return (
    <>
      <h1>{mixtape.name}</h1>
      <p class="sub">{items.length} {items.length === 1 ? "tune" : "tunes"}{seconds ? ` · ${mins(seconds)}` : ""}{mixtape.is_private ? " · private" : ""} · <a href={`/heads/${head.handle}/mixtapes/${mixtape.id}`}>how heads see it</a></p>
      {ok ? <Ok>{ok}</Ok> : null}{error ? <Err>{error}</Err> : null}
      {items.length ? <div class="btns"><a class="btn btn-red" href={`/heads/${head.handle}/mixtapes/${mixtape.id}`} data-mix={mixtape.id}>Spin the mix tape</a></div> : null}
      <form method="post" action={`/me/mixtapes/${mixtape.id}`}>
        <label for="name">Name</label>
        <input id="name" name="name" value={mixtape.name} maxlength={60} required />
        <label for="blurb">A line about it</label>
        <input id="blurb" name="blurb" value={mixtape.blurb} maxlength={300} />
        <label><input type="checkbox" name="is_private" value="1" checked={!!mixtape.is_private} /> Keep it private</label>
        <div class="btns"><button class="btn btn-red" type="submit">Save</button></div>
      </form>
      <h2>Tunes</h2>
      {items.length === 0 ? <Empty>Nothing on it yet. Open any tape and put a tune on it.</Empty> : (
        <ol class="rows">
          {items.map((it, i) => (
            <li>
              <a class="d" href={`/shows/${it.show_date_string}/${it.show_identifier}`}>{prettyDate(it.show_date_string)}</a> · {it.track_title} · {mmss(it.duration_seconds)}
              {" "}
              <form method="post" action={`/me/mixtapes/${mixtape.id}/items/${it.id}/move`} class="inline">
                <button class="btn" name="dir" value="up" type="submit" disabled={i === 0} aria-label="Move up">↑</button>
                <button class="btn" name="dir" value="down" type="submit" disabled={i === items.length - 1} aria-label="Move down">↓</button>
              </form>{" "}
              <form method="post" action={`/me/mixtapes/${mixtape.id}/items/${it.id}/delete`} class="inline"><button class="btn" type="submit">Take it off</button></form>
            </li>
          ))}
        </ol>
      )}
      <h2>Tree</h2>
      {mixtape.is_private ? <p class="help">Private mix tapes can't be treed. Make it public first.</p>
        : tree ? <p>This mix tape is a tree with {tree.members} {tree.members === 1 ? "head" : "heads"} on it. <a href={`/trees/${tree.id}`}>The tree</a></p>
        : <form method="post" action={`/me/mixtapes/${mixtape.id}/tree`}><p class="help">A tree is a tape list that gets passed around. Start one and other heads can get on it.</p><div class="btns"><button class="btn" type="submit">Start a tree from this mix tape</button></div></form>}
      <h2>Toss it</h2>
      <p class="help">The tunes stay on archive.org. Only the list goes.</p>
      <div class="btns"><a class="btn" href={`/me/mixtapes/${mixtape.id}/toss`}>Toss the mix tape</a></div>
      <p class="meta"><a href="/me/mixtapes">← Mix Tapes</a></p>
    </>
  );
};

export const Confirm: FC<{ title: string; body: string; action: string; yes: string; back: string }> = ({ title, body, action, yes, back }) => (
  <>
    <h1>{title}</h1>
    <p>{body}</p>
    <form method="post" action={action}>
      <div class="btns"><button class="btn btn-red" type="submit">{yes}</button><a class="btn" href={back}>Keep it</a></div>
    </form>
  </>
);

export const ShelfPage: FC<{ owner: string; shelf: Shelf; items: ShelfItem[]; mine: boolean; tree: TreeState | null; viewer: Head | null }> = ({ owner, shelf, items, mine, tree, viewer }) => (
  <>
    <h1>{shelf.name}</h1>
    <p class="sub"><a href={`/heads/${owner}`}>{owner}</a> · {items.length} {items.length === 1 ? "tape" : "tapes"}{shelf.is_private ? " · private" : ""}{mine ? <> · <a href={`/me/shelves/${shelf.id}`}>Edit</a></> : null}</p>
    {shelf.blurb ? <p>{shelf.blurb}</p> : null}
    {items.length === 0 ? <Empty>Nothing on it yet.</Empty> : (
      <ol class="rows">
        {items.map((it) => (
          <li>
            <a class="d" href={it.show_id ? `/shows/${it.show_id}` : `https://archive.org/details/${it.show_identifier}`}>{it.show_date ? prettyDate(it.show_date) : it.show_identifier}</a> · {it.display_name.replace(/^\S+\s*/, "")}
            {" · "}<a href={`https://archive.org/details/${it.show_identifier}`} data-spin={it.show_identifier}>Spin</a>
          </li>
        ))}
      </ol>
    )}
    <TreeBlock tree={tree} viewer={viewer} mine={mine} />
  </>
);

export const MixtapePage: FC<{ owner: string; mixtape: Mixtape; items: MixtapeItem[]; mine: boolean; tree: TreeState | null; viewer: Head | null }> = ({ owner, mixtape, items, mine, tree, viewer }) => {
  const seconds = items.reduce((n, i) => n + (i.duration_seconds || 0), 0);
  return (
    <>
      <h1>{mixtape.name}</h1>
      <p class="sub"><a href={`/heads/${owner}`}>{owner}</a> · mix tape · {items.length} {items.length === 1 ? "tune" : "tunes"}{seconds ? ` · ${mins(seconds)}` : ""}{mixtape.is_private ? " · private" : ""}{mine ? <> · <a href={`/me/mixtapes/${mixtape.id}`}>Edit</a></> : null}</p>
      {mixtape.blurb ? <p>{mixtape.blurb}</p> : null}
      {items.length ? <div class="btns"><a class="btn btn-red" href={`/shows/${items[0]!.show_date_string}/${items[0]!.show_identifier}`} data-mix={mixtape.id}>Spin the mix tape</a></div> : null}
      {items.length === 0 ? <Empty>Nothing on it yet.</Empty> : (
        <ol class="rows">
          {items.map((it) => (
            <li><a class="d" href={`/shows/${it.show_date_string}/${it.show_identifier}`}>{prettyDate(it.show_date_string)}</a> · {it.track_title} · {mmss(it.duration_seconds)} · <span class="meta">{it.show_display_name.replace(/^\S+\s*/, "")}</span></li>
          ))}
        </ol>
      )}
      <TreeBlock tree={tree} viewer={viewer} mine={mine} />
    </>
  );
};

const TreeBlock: FC<{ tree: TreeState | null; viewer: Head | null; mine: boolean }> = ({ tree, viewer, mine }) => {
  if (!tree) return null;
  return (
    <>
      <h2>Tree</h2>
      <p>{tree.members} {tree.members === 1 ? "head is" : "heads are"} on this tree. <a href={`/trees/${tree.id}`}>The tree</a></p>
      {!mine && viewer && !tree.joined ? <form method="post" action={`/trees/${tree.id}/join`}><div class="btns"><button class="btn btn-red" type="submit">Get on the tree</button></div></form> : null}
      {!mine && !viewer ? <p class="help"><a href="/signin" data-full>Sign in</a> to get on the tree.</p> : null}
    </>
  );
};

export const MeJournal: FC<{ head: Head; entries: JournalEntry[]; show?: { show_id: string; label: string } | null; error?: string | null; draft?: string }> = ({ head, entries, show, error, draft }) => (
  <>
    <h1>Journal</h1>
    <p class="sub">Private. Nobody sees this but you.</p>
    {error ? <Err>{error}</Err> : null}
    <form method="post" action="/me/journal">
      <label for="show">The show</label>
      <input id="show" name="show" value={show?.show_id ?? ""} placeholder="5/8/77" required aria-describedby="show-help" />
      <p class="help" id="show-help">{show ? show.label : "A date like 5/8/77."}</p>
      <label for="body">What happened</label>
      <textarea id="body" name="body" required maxlength={8000}>{draft ?? ""}</textarea>
      <label for="mood">A word for it</label>
      <input id="mood" name="mood" maxlength={30} placeholder="hot, mellow, spacey…" />
      <div class="btns"><button class="btn btn-red" type="submit">Write it down</button></div>
    </form>
    <h2>Entries</h2>
    {entries.length === 0 ? <Empty>Nothing in the journal yet.</Empty> : entries.map((e) => (
      <div class="note" id={`j${e.id}`}>
        <div class="hdr"><b>{e.show_id ? <a href={`/shows/${e.show_id}`}>{e.show_display_name}</a> : e.show_display_name}</b>{e.mood ? ` · ${e.mood}` : ""} · written {prettyDate(e.created_at)} · <a href={`/me/journal/${e.id}`}>Edit</a></div>
        <pre>{e.body}</pre>
      </div>
    ))}
    <p class="meta"><a href="/me">← Your page</a></p>
  </>
);

export const MeJournalEntry: FC<{ head: Head; entry: JournalEntry; error?: string | null }> = ({ entry, error }) => (
  <>
    <h1>{entry.show_display_name}</h1>
    <p class="sub">Written {prettyDate(entry.created_at)}</p>
    {error ? <Err>{error}</Err> : null}
    <form method="post" action={`/me/journal/${entry.id}`}>
      <label for="body">What happened</label>
      <textarea id="body" name="body" required maxlength={8000}>{entry.body}</textarea>
      <label for="mood">A word for it</label>
      <input id="mood" name="mood" value={entry.mood ?? ""} maxlength={30} />
      <div class="btns"><button class="btn btn-red" type="submit">Save</button><a class="btn" href="/me/journal">Back</a></div>
    </form>
    <form method="post" action={`/me/journal/${entry.id}/delete`}><div class="btns"><button class="btn" type="submit">Pull it</button></div></form>
  </>
);

export const TapeLists: FC<{ shelves: { id: string; name: string; owner: string; n: number; updated_at: string }[]; mixtapes: { id: string; name: string; owner: string; n: number; seconds: number; updated_at: string }[]; trees: { id: string; kind: string; name: string; owner: string; members: number }[] }> = ({ shelves, mixtapes, trees }) => (
  <>
    <h1>Tape Lists</h1>
    <p class="sub">What the heads keep on the shelf, and the trees passing it around.</p>
    <h2>Trees</h2>
    {trees.length === 0 ? <Empty>No trees yet. Start one from any shelf or mix tape of yours.</Empty> : (
      <ol class="rows">{trees.map((t) => <li><a href={`/trees/${t.id}`}>{t.name}</a> · {t.kind === "shelf" ? "a shelf" : "a mix tape"} · {t.members} {t.members === 1 ? "head" : "heads"} · started by <a href={`/heads/${t.owner}`}>{t.owner}</a></li>)}</ol>
    )}
    <h2>Shelves</h2>
    {shelves.length === 0 ? <Empty>No public shelves yet.</Empty> : (
      <ol class="rows">{shelves.map((s) => <li><a href={`/heads/${s.owner}/shelves/${s.id}`}>{s.name}</a> · {s.n} {s.n === 1 ? "tape" : "tapes"} · <a href={`/heads/${s.owner}`}>{s.owner}</a></li>)}</ol>
    )}
    <h2>Mix Tapes</h2>
    {mixtapes.length === 0 ? <Empty>No public mix tapes yet.</Empty> : (
      <ol class="rows">{mixtapes.map((m) => <li><a href={`/heads/${m.owner}/mixtapes/${m.id}`}>{m.name}</a> · {m.n} {m.n === 1 ? "tune" : "tunes"}{m.seconds ? ` · ${mins(m.seconds)}` : ""} · <a href={`/heads/${m.owner}`}>{m.owner}</a>{m.n ? <> · <a href={`/heads/${m.owner}/mixtapes/${m.id}`} data-mix={m.id}>Spin</a></> : null}</li>)}</ol>
    )}
  </>
);
