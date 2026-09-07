/** Getting on the bus, signing in, and getting back on with the recovery code. */
import type { FC } from "hono/jsx";
import { NODE_PICKS } from "../auth/handles";
import { Err } from "./parts";

export const Bus: FC<{ node?: string; name?: string; firstShow?: string; error?: string | null }> = ({ node = "", name = "", firstShow = "", error }) => (
  <>
    <h1>Get on the Bus</h1>
    <p class="sub">Apple ID, or a handle and a passkey. No email, no password.</p>
    {error ? <Err>{error}</Err> : null}
    <div class="btns">
      <button class="btn btn-red" type="button" data-apple="signin" data-next="/me?welcome=1">Sign in with Apple</button>
      <span class="help">One tap. We pick you a handle; change it once if you like.</span>
    </div>
    <p class="err" data-error hidden></p>
    <h2>Or pick a handle and make a passkey</h2>
    <form method="post" action="/bus" id="bus" data-full>
      <fieldset>
        <legend>Your handle</legend>
        <label for="node">Node</label>
        <input id="node" name="node" list="nodes" value={node} maxlength={12} autocapitalize="characters" autocomplete="off" required aria-describedby="node-help" />
        <datalist id="nodes">{NODE_PICKS.map((n) => <option value={n} />)}</datalist>
        <p class="help" id="node-help">Pick one of the old nodes or make up your own. Two to twelve letters.</p>
        <label for="name">Name</label>
        <input id="name" name="name" value={name} maxlength={12} autocapitalize="characters" autocomplete="username" required aria-describedby="name-help" />
        <p class="help" id="name-help">Your handle will look like PHISH::HUSSEY. Letters, digits and underscore, like the old nodes.</p>
      </fieldset>
      <label for="first_show">When did the bus come by for you?</label>
      <input id="first_show" name="first_show" value={firstShow} placeholder="5/8/77, or a year" aria-describedby="first-help" />
      <p class="help" id="first-help">Optional. A date like 5/8/77, a year, or leave it blank.</p>
      <div class="btns">
        <button class="btn btn-red" type="submit" data-webauthn="signup">Make your passkey</button>
        <span class="help">Your phone or computer keeps the passkey; we never see a password.</span>
      </div>
      <noscript><p class="err">Passkeys need JavaScript. Turn it on for this page and try again.</p></noscript>
    </form>
    <section id="welcome" hidden>
      <h2>Write this on the J-card</h2>
      <p class="code" data-code></p>
      <p>That's your recovery code. This is the only time it's shown. Lose the passkey and the code and the handle's gone for good.</p>
      <div class="btns"><a class="btn btn-red" href="/me" data-full>I wrote it down</a></div>
    </section>
    <p class="help">Been here before? <a href="/signin" data-full>Sign in</a>.</p>
  </>
);

export const SignIn: FC<{ next?: string; error?: string | null }> = ({ next, error }) => (
  <>
    <h1>Sign in</h1>
    <p class="sub">Apple ID or passkey. No email, no password.</p>
    {error ? <Err>{error}</Err> : null}
    <div class="btns">
      <button class="btn btn-red" type="button" data-apple="signin" data-next={next ?? "/me"}>Sign in with Apple</button>
      <span class="help">One tap with Face ID or Touch ID. Same Apple ID on the iPhone app means the same shelves.</span>
    </div>
    <p class="err" data-error hidden></p>
    <p class="help">Or use a passkey:</p>
    <form method="post" action="/signin" id="signin" data-full>
      <input type="hidden" name="next" value={next ?? "/me"} />
      <label for="handle">Handle</label>
      <input id="handle" name="handle" placeholder="NODE::NAME" autocapitalize="characters" autocomplete="username webauthn" aria-describedby="handle-help" />
      <p class="help" id="handle-help">Optional. Leave it blank and pick the passkey when your browser asks.</p>
      <div class="btns"><button class="btn btn-red" type="submit" data-webauthn="signin">Sign in with your passkey</button></div>
      <noscript><p class="err">Passkeys need JavaScript. Use your recovery code below.</p></noscript>
    </form>
    <details>
      <summary>Lost your passkey?</summary>
      <p>The recovery code from the J-card gets you back on and makes a new passkey.</p>
      <div class="btns"><a class="btn" href="/recover" data-full>Use the recovery code</a></div>
    </details>
    <p class="help">New here? <a href="/bus" data-full>Get on the Bus</a>.</p>
  </>
);

export const Recover: FC<{ handle?: string; error?: string | null }> = ({ handle = "", error }) => (
  <>
    <h1>Back on the bus</h1>
    <p class="sub">The handle and the code you wrote on the J-card.</p>
    {error ? <Err>{error}</Err> : null}
    <form method="post" action="/recover" data-full>
      <label for="handle">Handle</label>
      <input id="handle" name="handle" value={handle} placeholder="NODE::NAME" autocapitalize="characters" required />
      <label for="code">Recovery code</label>
      <input id="code" name="code" placeholder="NHXX-XXXX-XXXX-XXXX-XXXX" autocapitalize="characters" autocomplete="off" required />
      <div class="btns"><button class="btn btn-red" type="submit">Get back on</button></div>
    </form>
  </>
);

/** The page that mints a new passkey after the code checked out. */
export const RecoverPasskey: FC<{ handle: string; ceremonyId: string; optionsJson: string }> = ({ handle, ceremonyId, optionsJson }) => (
  <>
    <h1>{handle}, welcome back.</h1>
    <p>The code checked out. One more thing: a new passkey for this phone or computer.</p>
    <div class="btns"><button class="btn btn-red" type="button" data-webauthn="recover" data-ceremony={ceremonyId}>Make a new passkey</button></div>
    <script type="application/json" id="ceremony-options">{optionsJson}</script>
    <p class="err" data-error hidden></p>
    <section id="welcome" hidden>
      <h2>Write this on the J-card</h2>
      <p class="code" data-code></p>
      <p>A fresh recovery code. The old one is dead. This is the only time it's shown.</p>
      <div class="btns"><a class="btn btn-red" href="/me/passkeys" data-full>I wrote it down</a></div>
    </section>
    <noscript><p class="err">Passkeys need JavaScript. Turn it on and reload this page.</p></noscript>
  </>
);

export const NewCode: FC<{ code: string }> = ({ code }) => (
  <>
    <h1>Write this on the J-card</h1>
    <p class="code">{code}</p>
    <p>A fresh recovery code. The old one stopped working the moment this one was made. This is the only time it's shown.</p>
    <div class="btns"><a class="btn btn-red" href="/me/passkeys">I wrote it down</a></div>
  </>
);
