/** A tree: a tape list passed around, and who's on it. */
import type { FC } from "hono/jsx";
import type { Head } from "../env";
import type { MixtapeItem, ShelfItem } from "../tapes/store";
import { mins, mmss, prettyDate } from "../fmt";
import { Empty } from "./parts";

export interface TreeRow { id: string; owner_id: string; owner: string; kind: "shelf" | "mixtape"; source_id: string; name: string; blurb: string; created_at: string }

export const TreePage: FC<{ tree: TreeRow; shelfItems: ShelfItem[]; mixItems: MixtapeItem[]; members: { handle: string; joined_at: string }[]; viewer: Head | null; joined: boolean }> = ({ tree, shelfItems, mixItems, members, viewer, joined }) => {
  const mine = viewer?.id === tree.owner_id;
  const seconds = mixItems.reduce((n, i) => n + (i.duration_seconds || 0), 0);
  return (
    <>
      <h1>{tree.name}</h1>
      <p class="sub">{tree.kind === "shelf" ? "A shelf" : "A mix tape"} · started by <a href={`/heads/${tree.owner}`}>{tree.owner}</a> · {members.length} {members.length === 1 ? "head" : "heads"} on it · since {prettyDate(tree.created_at)}</p>
      <p>A tree is a tape list that gets passed around. Get on it and it shows up on your page, and every tape the owner adds turns up in <a href="/me/tree">On the tree</a>.</p>
      {tree.blurb ? <p>{tree.blurb}</p> : null}
      {!mine && viewer && !joined ? <form method="post" action={`/trees/${tree.id}/join`}><div class="btns"><button class="btn btn-red" type="submit">Get on the tree</button></div></form> : null}
      {!mine && viewer && joined ? <form method="post" action={`/trees/${tree.id}/leave`}><div class="btns"><button class="btn" type="submit">Get off the tree</button></div></form> : null}
      {!viewer ? <p class="help"><a href="/signin" data-full>Sign in</a> to get on the tree.</p> : null}
      {mine ? <p class="help">Your tree. Add tapes from <a href={tree.kind === "shelf" ? `/me/shelves/${tree.source_id}` : `/me/mixtapes/${tree.source_id}`}>the {tree.kind === "shelf" ? "shelf" : "mix tape"}</a>.</p> : null}

      <h2>{tree.kind === "shelf" ? "Tapes" : "Tunes"}</h2>
      {tree.kind === "shelf" ? (shelfItems.length === 0 ? <Empty>Nothing on it yet.</Empty> : (
        <ol class="rows">
          {shelfItems.map((it) => <li><a class="d" href={it.show_id ? `/shows/${it.show_id}` : `https://archive.org/details/${it.show_identifier}`}>{it.show_date ? prettyDate(it.show_date) : it.show_identifier}</a> · {it.display_name.replace(/^\S+\s*/, "")} · <a href={`https://archive.org/details/${it.show_identifier}`} data-spin={it.show_identifier}>Spin</a></li>)}
        </ol>
      )) : (mixItems.length === 0 ? <Empty>Nothing on it yet.</Empty> : (
        <>
          <div class="btns"><a class="btn btn-red" href={`/heads/${tree.owner}/mixtapes/${tree.source_id}`} data-mix={tree.source_id}>Spin the mix tape</a><span class="help">{mins(seconds)}</span></div>
          <ol class="rows">
            {mixItems.map((it) => <li><a class="d" href={`/shows/${it.show_date_string}/${it.show_identifier}`}>{prettyDate(it.show_date_string)}</a> · {it.track_title} · {mmss(it.duration_seconds)}</li>)}
          </ol>
        </>
      ))}

      <h2>Heads on the Tree</h2>
      {members.length === 0 ? <Empty>Nobody's on it yet but {tree.owner}.</Empty> : (
        <ol class="rows">{members.map((m) => <li><a href={`/heads/${m.handle}`}>{m.handle}</a> · since {prettyDate(m.joined_at)}</li>)}</ol>
      )}
      {mine ? <form method="post" action={`/trees/${tree.id}/close`}><h2>Close it</h2><p class="help">The {tree.kind === "shelf" ? "shelf" : "mix tape"} stays yours; the tree stops passing it around.</p><div class="btns"><button class="btn" type="submit">Close the tree</button></div></form> : null}
    </>
  );
};

export interface FeedRow { tree_id: string; tree_name: string; owner: string; kind: string; show_id: string | null; show_identifier: string; label: string; added_at: string; file_name: string | null; show_date: string | null }

export const OnTheTree: FC<{ rows: FeedRow[]; trees: { id: string; name: string; owner: string }[] }> = ({ rows, trees }) => (
  <>
    <h1>On the Tree</h1>
    <p class="sub">What's turned up on the trees you're on, newest first.</p>
    {trees.length === 0 ? <Empty>You're not on any trees. Find one under <a href="/tapelists">Tape Lists</a>.</Empty> : (
      <p class="meta">{trees.map((t, i) => <>{i ? " · " : ""}<a href={`/trees/${t.id}`}>{t.name}</a></>)}</p>
    )}
    {rows.length === 0 && trees.length ? <Empty>Nothing new since you got on. Check back after the weekend.</Empty> : null}
    {rows.length ? (
      <ol class="rows">
        {rows.map((r) => (
          <li>
            <a class="d" href={r.show_id ? `/shows/${r.show_id}` : `/shows/${r.show_date ?? ""}/${r.show_identifier}`}>{r.show_date ? prettyDate(r.show_date) : r.show_identifier}</a> · {r.label}
            {" · "}<a href={`https://archive.org/details/${r.show_identifier}`} data-spin={r.show_identifier}>Spin</a>
            {" · "}<span class="meta">on <a href={`/trees/${r.tree_id}`}>{r.tree_name}</a> · {prettyDate(r.added_at)}</span>
          </li>
        ))}
      </ol>
    ) : null}
  </>
);
