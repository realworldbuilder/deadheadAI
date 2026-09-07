/** The back room. Plain tables, no cleverness. */
import type { FC } from "hono/jsx";
import type { Head } from "../env";
import { noteNumber, prettyDate } from "../fmt";
import { Ok } from "./parts";

export interface AdminCounts { heads: number; notes: number; shelves: number; mixtapes: number; trees: number; spins24h: number; sessions: number }
export interface AdminHead { id: string; handle: string; created_at: string; disabled_at: string | null; role: string; notes: number; passkeys: number; last_seen: string | null }
export interface AdminNote { id: number; topic_id: number; reply_no: number; handle: string | null; show_id: string; created_at: string; deleted_by: string | null; body: string }

export const AdminHome: FC<{ head: Head; counts: AdminCounts; catalog: Record<string, string> }> = ({ counts, catalog }) => (
  <>
    <h1>Admin</h1>
    <p class="meta">Catalog schema {catalog.schema_version ?? "?"} · {catalog.show_count ?? "?"} shows · {catalog.recording_count ?? "?"} tapes · {catalog.digest_count ?? "?"} digests · built {catalog.generated_at ? prettyDate(catalog.generated_at.slice(0, 10)) : "?"} · exported {catalog.exported_at ? prettyDate(catalog.exported_at.slice(0, 10)) : "?"}</p>
    <table class="admin">
      <tbody>
        <tr><td>Heads</td><td>{counts.heads}</td></tr>
        <tr><td>Notes</td><td>{counts.notes}</td></tr>
        <tr><td>Shelves</td><td>{counts.shelves}</td></tr>
        <tr><td>Mix tapes</td><td>{counts.mixtapes}</td></tr>
        <tr><td>Trees</td><td>{counts.trees}</td></tr>
        <tr><td>In the lot, last 24 h</td><td>{counts.spins24h}</td></tr>
        <tr><td>Live sessions</td><td>{counts.sessions}</td></tr>
      </tbody>
    </table>
    <p class="meta"><a href="/admin/heads">Heads</a> · <a href="/admin/notes">Notes</a></p>
  </>
);

export const AdminHeads: FC<{ heads: AdminHead[]; q: string; ok?: string | null }> = ({ heads, q, ok }) => (
  <>
    <h1>Heads</h1>
    {ok ? <Ok>{ok}</Ok> : null}
    <form method="get" action="/admin/heads" data-full>
      <label for="q">Find a handle</label>
      <input id="q" name="q" value={q} />
    </form>
    <div class="scroll">
      <table class="admin">
        <thead><tr><th>Handle</th><th>Joined</th><th>Notes</th><th>Keys</th><th>Last seen</th><th>State</th><th></th></tr></thead>
        <tbody>
          {heads.map((h) => (
            <tr>
              <td><a href={`/heads/${h.handle}`}>{h.handle}</a>{h.role === "admin" ? " · admin" : ""}</td>
              <td>{prettyDate(h.created_at)}</td>
              <td>{h.notes}</td>
              <td>{h.passkeys}</td>
              <td>{h.last_seen ? prettyDate(h.last_seen) : "—"}</td>
              <td>{h.disabled_at ? "frozen" : "on the bus"}</td>
              <td>
                {h.disabled_at
                  ? <form method="post" action={`/admin/heads/${h.handle}/enable`} class="inline" data-full><button class="btn" type="submit">Thaw</button></form>
                  : <form method="post" action={`/admin/heads/${h.handle}/disable`} class="inline" data-full><button class="btn" type="submit">Freeze</button></form>}
                {" "}
                <form method="post" action={`/admin/heads/${h.handle}/delete`} class="inline" data-full>
                  <input name="confirm_handle" placeholder="type handle" style="max-width:10em" />
                  <button class="btn" type="submit">Erase</button>
                </form>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
    <p class="meta"><a href="/admin">← Admin</a></p>
  </>
);

export const AdminNotes: FC<{ notes: AdminNote[]; older: number | null; ok?: string | null }> = ({ notes, older, ok }) => (
  <>
    <h1>Notes</h1>
    {ok ? <Ok>{ok}</Ok> : null}
    <div class="scroll">
      <table class="admin">
        <thead><tr><th>Number</th><th>Head</th><th>Show</th><th>Posted</th><th>Note</th><th></th></tr></thead>
        <tbody>
          {notes.map((n) => (
            <tr>
              <td><a href={`/notes/${noteNumber(n.topic_id, n.reply_no)}`}>{noteNumber(n.topic_id, n.reply_no)}</a></td>
              <td>{n.handle ?? "—"}</td>
              <td><a href={`/shows/${n.show_id}`}>{prettyDate(n.show_id)}</a></td>
              <td>{prettyDate(n.created_at)}</td>
              <td style="white-space:normal">{n.deleted_by ? <i>pulled ({n.deleted_by})</i> : n.body.slice(0, 120)}</td>
              <td>{n.deleted_by ? null : <form method="post" action={`/admin/notes/${noteNumber(n.topic_id, n.reply_no)}/delete`} class="inline" data-full><button class="btn" type="submit">Pull</button></form>}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
    {older ? <p class="meta"><a href={`/admin/notes?before=${older}`}>Older →</a></p> : null}
    <p class="meta"><a href="/admin">← Admin</a></p>
  </>
);
