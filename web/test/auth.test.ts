import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { SoftAuthenticator } from "./softauth";
import { parseHandle } from "../src/auth/handles";
import { generateRecoveryCode, normalizeCode, verifyCode, hashCode } from "../src/auth/recovery";

import { ORIGIN, cookieOf, form, get, json, signIn, signUp } from "./helpers";

describe("handles", () => {
  it("take the DECnotes form", () => {
    expect(parseHandle("phish::hussey")).toEqual({ handle: "PHISH::HUSSEY", node: "PHISH", name: "HUSSEY" });
    expect(parseHandle("cslall::henderson")).toMatchObject({ handle: "CSLALL::HENDERSON" });
    expect("error" in parseHandle("hussey")).toBe(true);
    expect("error" in parseHandle("X::Y")).toBe(true);
    expect("error" in parseHandle("PHISH::ABCDEFGHIJKLM")).toBe(true);
    expect("error" in parseHandle("RDVAX::HUSSEY")).toBe(true);
    expect("error" in parseHandle("RDVAX::HUSSEY", { allowReserved: true })).toBe(false);
    expect("error" in parseHandle("__::HUSSEY")).toBe(true);
  });
});

describe("recovery codes", () => {
  it("look like NHXX-XXXX-XXXX-XXXX-XXXX and fold look-alikes", async () => {
    const code = generateRecoveryCode();
    expect(code).toMatch(/^NH[0-9A-HJKMNP-TV-Z]{2}(-[0-9A-HJKMNP-TV-Z]{4}){4}$/);
    expect(normalizeCode("nh0o-ii1l")).toBe("NH001111");
    const hash = await hashCode(code);
    expect(await verifyCode(code.toLowerCase().replace(/-/g, " "), hash)).toBe(true);
    expect(await verifyCode(generateRecoveryCode(), hash)).toBe(false);
  });
});

describe("getting on the bus", () => {
  it("signs up, signs in, adds a passkey, recovers, signs out everywhere, leaves", async () => {
    const auth = new SoftAuthenticator();
    const { cookie, handle, code, credentialId } = await signUp(auth, "phish", "hussey");
    expect(handle).toBe("PHISH::HUSSEY");
    expect(cookie).toMatch(/^__Host-nh_session=/);

    // /me knows us
    const mePage = await get("/me", cookie);
    expect(mePage.status).toBe(200);
    const meHtml = await mePage.text();
    expect(meHtml).toContain("PHISH::HUSSEY");
    expect(meHtml).toContain("5/8/77");

    // the handle is taken now
    const dup = await json("/bus/options", { node: "PHISH", name: "hussey" });
    expect(dup.status).toBe(409);

    // sign in with the passkey, discoverable (no handle) and by handle
    const s1 = await signIn(auth, undefined, credentialId);
    expect(s1.res.status).toBe(200);
    expect((await s1.res.json<{ next: string }>()).next).toBe("/me");
    const s2 = await signIn(auth, "phish::hussey", credentialId);
    expect(s2.res.status).toBe(200);

    // a replayed assertion (counter goes backwards) is refused
    const o = await json("/signin/options", { handle });
    const { ceremonyId, options } = await o.json<{ ceremonyId: string; options: any }>();
    const cred = auth.creds.get(credentialId)!;
    cred.counter = 0;
    const replay = await auth.get(options, ORIGIN, credentialId);
    const rv = await json("/signin/verify", { ceremonyId, credential: replay });
    expect(rv.status).toBe(400);

    // a ceremony can't be used twice
    const again = await json("/signin/verify", { ceremonyId, credential: replay });
    expect(again.status).toBe(400);

    // add a second passkey
    const ao = await json("/me/passkeys/options", {}, cookie);
    expect(ao.status).toBe(200);
    const addOpts = await ao.json<{ ceremonyId: string; options: any }>();
    expect(addOpts.options.excludeCredentials.map((c: { id: string }) => c.id)).toContain(credentialId);
    const second = await auth.create(addOpts.options, ORIGIN);
    const av = await json("/me/passkeys/verify", { ceremonyId: addOpts.ceremonyId, credential: second }, cookie);
    expect(av.status).toBe(200);
    const list = await env.NOTES.prepare("SELECT COUNT(*) AS n FROM passkeys").first<{ n: number }>();
    expect(list?.n).toBe(2);

    // can't drop the last passkey without the box ticked
    const del1 = await form(`/me/passkeys/${encodeURIComponent(credentialId)}/delete`, {}, cookie);
    expect(del1.status).toBe(303);
    const del2 = await form(`/me/passkeys/${encodeURIComponent(second.id)}/delete`, {}, cookie);
    expect(del2.status).toBe(303);
    expect(del2.headers.get("location")).toContain("error=");
    const del3 = await form(`/me/passkeys/${encodeURIComponent(second.id)}/delete`, { have_recovery_code: "1" }, cookie);
    expect(del3.headers.get("location")).toContain("ok=removed");

    // recovery: wrong code fails, right code mints a passkey and a new code
    const bad = await form("/recover", { handle, code: "NH00-0000-0000-0000-0000" });
    expect(bad.status).toBe(400);
    const good = await form("/recover", { handle, code });
    expect(good.status).toBe(200);
    const html = await good.text();
    const cid = /data-ceremony="([^"]+)"/.exec(html)![1]!;
    const opts = JSON.parse(/<script type="application\/json" id="ceremony-options">([\s\S]*?)<\/script>/.exec(html)![1]!.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&"));
    const third = await auth.create(opts, ORIGIN);
    const rr = await json("/recover/verify", { ceremonyId: cid, credential: third });
    expect(rr.status, await rr.clone().text()).toBe(200);
    const recovered = await rr.json<{ recoveryCode: string }>();
    expect(recovered.recoveryCode).not.toBe(code);
    const newCookie = cookieOf(rr);
    // the old code is dead, the old session is dead
    const dead = await form("/recover", { handle, code });
    expect(dead.status).toBe(400);
    expect((await get("/me", cookie)).status).toBe(303);
    expect((await get("/me", newCookie)).status).toBe(200);

    // sign out everywhere
    const out = await form("/signout/everywhere", {}, newCookie);
    expect(out.status).toBe(303);
    expect((await get("/me", newCookie)).status).toBe(303);

    // back in, then leave the bus
    const s3 = await signIn(auth, handle, third.id);
    expect(s3.res.status).toBe(200);
    const leaveWrong = await form("/me/delete", { confirm_handle: "NOPE::NOPE" }, s3.cookie);
    expect(leaveWrong.status).toBe(400);
    const leave = await form("/me/delete", { confirm_handle: "phish::hussey" }, s3.cookie);
    expect(leave.status).toBe(303);
    for (const table of ["users", "passkeys", "sessions", "ceremonies"]) {
      const n = await env.NOTES.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first<{ n: number }>();
      expect(n?.n, table).toBe(0);
    }
    // the handle is free again
    const free = await json("/bus/options", { node: "PHISH", name: "hussey" });
    expect(free.status).toBe(200);
  });

  it("refuses cross-site JSON and bad handles", async () => {
    const cross = await SELF.fetch(ORIGIN + "/bus/options", { method: "POST", body: "{}", headers: { "content-type": "application/json", "sec-fetch-site": "cross-site" } });
    expect(cross.status).toBe(403);
    const bad = await json("/bus/options", { node: "RDVAX", name: "x" });
    expect(bad.status).toBe(400);
    const badDate = await json("/bus/options", { node: "PHISH", name: "someone", first_show: "yesterday" });
    expect(badDate.status).toBe(400);
  });

  it("throttles recovery guesses", async () => {
    const auth = new SoftAuthenticator();
    const { handle } = await signUp(auth, "nacad2", "siegel");
    for (let i = 0; i < 10; i++) await form("/recover", { handle, code: "NH00-0000-0000-0000-000" + i });
    const eleventh = await form("/recover", { handle, code: "NH00-0000-0000-0000-0000" });
    expect(eleventh.status).toBe(429);
  });

  it("a frozen head can't sign in", async () => {
    const auth = new SoftAuthenticator();
    const { handle, credentialId, cookie } = await signUp(auth, "cslall", "henderson");
    await env.NOTES.prepare("UPDATE users SET disabled_at=? WHERE handle=?").bind(new Date().toISOString(), handle).run();
    expect((await get("/me", cookie)).status).toBe(303);
    const s = await signIn(auth, handle, credentialId);
    expect(s.res.status).toBe(403);
  });

  it("the bus page and sign-in page render, with the passkey script", async () => {
    const bus = await get("/bus");
    expect(bus.status).toBe(200);
    const html = await bus.text();
    expect(html).toContain("Get on the Bus");
    expect(html).toContain("/bus.js");
    expect(html).toContain("PHISH::HUSSEY");
    const signin = await get("/signin");
    expect(await signin.text()).toContain("Lost your passkey?");
  });
});
