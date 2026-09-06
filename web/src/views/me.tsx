/** Your page: the bus question, the lot toggle, passkeys, the way off. */
import type { FC } from "hono/jsx";
import type { Head } from "../env";
import type { PasskeyRow } from "../auth/webauthn";
import { prettyDate } from "../fmt";
import { Err, Ok } from "./parts";

export const Me: FC<{ head: Head; saved?: boolean; error?: string | null; passkeyCount: number; counts: { notes: number; shelves: number; mixtapes: number; journal: number } }> = ({ head, saved, error, passkeyCount, counts }) => (
  <>
    <h1 class="topic">{head.handle}</h1>
    <p class="sub">Your page. <a href={`/heads/${head.handle}`}>How heads see it</a>.</p>
    {saved ? <Ok>Saved.</Ok> : null}
    {error ? <Err>{error}</Err> : null}
    <form method="post" action="/me">
      <label for="first_show">When did the bus come by for you?</label>
      <input id="first_show" name="first_show" value={head.firstShow ? (head.firstShow.length === 4 ? head.firstShow : prettyDate(head.firstShow)) : ""} placeholder="5/8/77, or a year" aria-describedby="first-help" />
      <p class="help" id="first-help">A date like 5/8/77, a year, or the show that did it. Blank is fine.</p>
      <label><input type="checkbox" name="share_spins" value="1" checked={head.shareSpins} /> Show me in the lot when I'm spinning</label>
      <div class="btns"><button class="btn btn-red" type="submit">Save</button></div>
    </form>

    <h2>Your tape list</h2>
    <ol class="rows">
      <li><a href="/me/shelves">Shelves</a> · {counts.shelves}</li>
      <li><a href="/me/mixtapes">Mix tapes</a> · {counts.mixtapes}</li>
      <li><a href="/me/journal">Journal</a> · {counts.journal} · private</li>
      <li><a href={`/heads/${head.handle}/notes`}>Notes</a> · {counts.notes}</li>
      <li><a href="/me/tree">On the tree</a></li>
    </ol>

    <h2>The Phone</h2>
    <p>Nethead on your iPhone can ride as this handle: same shelves, same mix tapes, same journal, and the phone shows up in the lot while it's spinning.</p>
    <form method="post" action="/me/pair"><div class="btns"><button class="btn btn-red" type="submit">Get the phone on the bus</button></div></form>

    <h2>Passkeys</h2>
    <p class="meta">{passkeyCount} {passkeyCount === 1 ? "passkey" : "passkeys"} · <a href="/me/passkeys" data-full>Manage passkeys and the recovery code</a></p>

    <h2>Off the bus</h2>
    <form method="post" action="/signout" class="inline"><button class="btn" type="submit">Sign out here</button></form>{" "}
    <form method="post" action="/signout/everywhere" class="inline"><button class="btn" type="submit">Sign out everywhere</button></form>
    <p class="help" style="margin-top:14px">Want the handle gone for good? <a href="/me/delete">Leave the bus</a>.</p>
  </>
);

export const Passkeys: FC<{ head: Head; passkeys: PasskeyRow[]; error?: string | null; ok?: string | null }> = ({ head, passkeys, error, ok }) => (
  <>
    <h1 class="topic">{head.handle} · passkeys</h1>
    {ok ? <Ok>{ok}</Ok> : null}
    {error ? <Err>{error}</Err> : null}
    <p class="err" data-error hidden></p>
    <ol class="rows">
      {passkeys.map((p) => (
        <li>
          <form method="post" action={`/me/passkeys/${encodeURIComponent(p.id)}`} class="inline" data-full>
            <label class="vh" for={`l-${p.id}`}>Label</label>
            <input id={`l-${p.id}`} name="label" value={p.label ?? ""} maxlength={40} style="max-width:12em" />
            <button class="btn" type="submit">Rename</button>
          </form>
          {" · added "}{prettyDate(p.created_at)}{p.last_used_at ? ` · used ${prettyDate(p.last_used_at)}` : ""}
          {" "}
          <form method="post" action={`/me/passkeys/${encodeURIComponent(p.id)}/delete`} class="inline" data-full>
            {passkeys.length === 1 ? <label style="display:inline;text-transform:none;letter-spacing:0"><input type="checkbox" name="have_recovery_code" value="1" /> I have my recovery code</label> : null}
            <button class="btn" type="submit">Remove</button>
          </form>
        </li>
      ))}
    </ol>
    <div class="btns"><button class="btn btn-red" type="button" data-webauthn="add">Add a passkey</button></div>
    <p class="help">A passkey on the phone and one on the Mac means you're never locked out. iCloud Keychain and Google carry the same passkey between devices.</p>

    <h2>Recovery</h2>
    <p>Lose every passkey and the recovery code gets you back on. If you never wrote it down, make a new one; the old one stops working.</p>
    <form method="post" action="/me/recovery/rotate" data-full><div class="btns"><button class="btn" type="submit">Make a new recovery code</button></div></form>
    <p class="meta"><a href="/me">← Your page</a></p>
  </>
);

export const LeaveBus: FC<{ head: Head; error?: string | null }> = ({ head, error }) => (
  <>
    <h1>Leave the bus?</h1>
    <p>This takes your shelves, mix tapes, journal and passkeys with it, and frees the handle. Your notes stay in the conference with no name on them. The tapes stay on archive.org. No undo.</p>
    {error ? <Err>{error}</Err> : null}
    <form method="post" action="/me/delete" data-full>
      <label for="confirm_handle">Type your handle to be sure</label>
      <input id="confirm_handle" name="confirm_handle" placeholder={head.handle} autocapitalize="characters" autocomplete="off" required />
      <div class="btns">
        <button class="btn btn-red" type="submit">Leave the bus</button>
        <a class="btn" href="/me">Stay</a>
      </div>
    </form>
  </>
);

export const PhoneCode: FC<{ head: Head; code: string }> = ({ head, code }) => (
  <>
    <h1>Get the phone on the bus</h1>
    <p>In Nethead on your iPhone, open Settings, tap <b>Get on the Bus</b> under Account, and type this code. It's good for ten minutes and works once.</p>
    <p class="code" style="font-size:28px">{code}</p>
    <p class="help">The phone rides as {head.handle} from then on. Sign it out from the phone's Settings, or from <a href="/me">your page</a> with “Sign out everywhere”.</p>
    <p class="meta"><a href="/me">← Your page</a></p>
  </>
);
