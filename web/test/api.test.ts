import { SELF, env } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { SignJWT, exportJWK, generateKeyPair, createLocalJWKSet } from "jose";
import { SoftAuthenticator } from "./softauth";
import { ORIGIN, form, get, signUp } from "./helpers";
import { APPLE_ISSUER, configureAppleKeys, freeHandle } from "../src/auth/apple";
import { sha256Hex } from "../src/db/ids";

const WEB_AUD = "com.deadhead.ai.web";
const APP_AUD = "com.deadhead.ai";

let privateKey: CryptoKey;
beforeAll(async () => {
  const pair = await generateKeyPair("RS256", { extractable: true });
  privateKey = pair.privateKey;
  const jwk = await exportJWK(pair.publicKey);
  configureAppleKeys(createLocalJWKSet({ keys: [{ ...jwk, kid: "test", alg: "RS256", use: "sig" }] }));
});

async function appleToken(opts: { sub: string; aud?: string; nonce?: string; iss?: string; expired?: boolean; email?: string }) {
  const jwt = new SignJWT({ nonce: opts.nonce, email: opts.email, email_verified: "true" })
    .setProtectedHeader({ alg: "RS256", kid: "test" })
    .setIssuer(opts.iss ?? APPLE_ISSUER)
    .setAudience(opts.aud ?? APP_AUD)
    .setSubject(opts.sub)
    .setIssuedAt(opts.expired ? Math.floor(Date.now() / 1000) - 7200 : undefined)
    .setExpirationTime(opts.expired ? Math.floor(Date.now() / 1000) - 3600 : "10m");
  return jwt.sign(privateKey);
}

const apiJson = (path: string, body: unknown, token?: string) => SELF.fetch(ORIGIN + path, {
  method: "POST", body: JSON.stringify(body), headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
});
const apiGet = (path: string, token?: string) => SELF.fetch(ORIGIN + path, { headers: token ? { authorization: `Bearer ${token}` } : {} });
const webJson = (path: string, body: unknown, cookie?: string) => SELF.fetch(ORIGIN + path, {
  method: "POST", body: JSON.stringify(body),
  headers: { "content-type": "application/json", "sec-fetch-site": "same-origin", origin: ORIGIN, ...(cookie ? { cookie } : {}) },
});
const cookieOf = (res: Response) => (res.headers.get("set-cookie") ?? "").split(";")[0]!;

async function phoneSignIn(sub: string, name?: string) {
  const { nonce } = await (await apiGet("/api/apple/nonce")).json<{ nonce: string }>();
  const token = await appleToken({ sub, aud: APP_AUD, nonce: await sha256Hex(nonce) });
  return apiJson("/api/apple", { identityToken: token, nonce, name, device: "iPhone 16 Pro" });
}

describe("Sign in with Apple", () => {
  it("makes a head on the phone, finds the same head on the web, syncs shelves between them", async () => {
    // the phone: bundle-id audience, hashed nonce
    const first = await phoneSignIn("001234.abcdef.5678", "Will");
    expect(first.status, await first.clone().text()).toBe(200);
    const { token, head } = await first.json<{ token: string; head: { id: string; handle: string; firstShow: string | null } }>();
    expect(head.handle).toBe("BUS::WILL");
    expect((await apiGet("/api/me", token)).status).toBe(200);
    const identity = await env.NOTES.prepare("SELECT user_id FROM identities WHERE provider='apple' AND subject=?").bind("001234.abcdef.5678").first<{ user_id: string }>();
    expect(identity!.user_id).toBe(head.id);

    // the same Apple ID again, from the phone: same head, new session
    const again = await phoneSignIn("001234.abcdef.5678");
    expect((await again.json<{ head: { id: string } }>()).head.id).toBe(head.id);

    // the website: web audience, raw nonce, cookie session
    const { nonce } = await (await SELF.fetch(ORIGIN + "/auth/apple/nonce", { headers: { "sec-fetch-site": "same-origin", origin: ORIGIN } })).json<{ nonce: string }>();
    const webToken = await appleToken({ sub: "001234.abcdef.5678", aud: WEB_AUD, nonce });
    const web = await webJson("/auth/apple", { idToken: webToken, nonce, next: "/me" });
    expect(web.status, await web.clone().text()).toBe(200);
    expect((await web.json<{ next: string }>()).next).toBe("/me");
    const cookie = cookieOf(web);
    const me = await get("/me", cookie);
    expect(me.status).toBe(200);
    const meHtml = await me.text();
    expect(meHtml).toContain("BUS::WILL");
    expect(meHtml).toContain("Signed in with Apple");
    expect(meHtml).toContain("Keep this handle");

    // shelves: pushed from the phone, seen on the web page, pulled back
    const shelfId = crypto.randomUUID().toUpperCase();
    const t0 = new Date(Date.now() - 60000).toISOString();
    const push = await apiJson("/api/sync", {
      shelves: [{ id: shelfId, name: "Phone Shelf", blurb: "", iconName: "heart.fill", isPrivate: false, createdAt: t0, updatedAt: t0, deletedAt: null }],
      shelfItems: [{ id: crypto.randomUUID().toUpperCase(), shelfId, showIdentifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", showId: null, showDate: "1977-05-08", displayName: "5/8/77 Barton Hall", sortIndex: 0, addedAt: t0, updatedAt: t0, deletedAt: null }],
    }, token);
    expect((await push.json<{ accepted: number }>()).accepted).toBe(2);
    expect(await (await get("/heads/BUS::WILL")).text()).toContain("Phone Shelf");
    await form("/me/shelves", { name: "Web Shelf" }, cookie);
    const pulled = await (await apiGet("/api/sync?since=0", token)).json<{ shelves: { name: string }[] }>();
    expect(pulled.shelves.map((s) => s.name).sort()).toEqual(["Phone Shelf", "Web Shelf"]);

    // the one-time rename, then it's fixed
    const renamed = await form("/me/handle", { handle: "shakedown::will" }, cookie);
    expect(renamed.headers.get("location")).toBe("/me?saved=1");
    expect((await apiGet("/api/me", token).then((r) => r.json<{ head: { handle: string } }>())).head.handle).toBe("SHAKEDOWN::WILL");
    await form("/shows/1977-05-08/notes", { body: "Spun it on the porch." }, cookie);
    expect(await (await get("/me", cookie)).text()).not.toContain("Keep this handle");

    // phone sign-out ends only the phone's session
    expect((await apiJson("/api/signout", {}, token)).status).toBe(204);
    expect((await apiGet("/api/me", token)).status).toBe(401);
    expect((await get("/me", cookie)).status).toBe(200);

    // leaving the bus takes the identity with it, and the Apple ID makes a fresh head next time
    await form("/me/delete", { confirm_handle: "shakedown::will" }, cookie);
    expect((await env.NOTES.prepare("SELECT COUNT(*) AS n FROM identities").first<{ n: number }>())!.n).toBe(0);
    const fresh = await phoneSignIn("001234.abcdef.5678", "Will");
    expect((await fresh.json<{ head: { id: string } }>()).head.id).not.toBe(head.id);
  });

  it("refuses bad tokens and stale nonces", async () => {
    const { nonce } = await (await apiGet("/api/apple/nonce")).json<{ nonce: string }>();
    const hashed = await sha256Hex(nonce);
    // wrong audience
    expect((await apiJson("/api/apple", { identityToken: await appleToken({ sub: "x1", aud: "com.someone.else", nonce: hashed }), nonce })).status).toBe(401);
    // wrong issuer
    expect((await apiJson("/api/apple", { identityToken: await appleToken({ sub: "x1", nonce: hashed, iss: "https://evil.example" }), nonce })).status).toBe(401);
    // expired
    expect((await apiJson("/api/apple", { identityToken: await appleToken({ sub: "x1", nonce: hashed, expired: true }), nonce })).status).toBe(401);
    // a nonce we never minted
    expect((await apiJson("/api/apple", { identityToken: await appleToken({ sub: "x1", nonce: "made-up" }), nonce: "made-up" })).status).toBe(400);
    // the right token, then the same nonce replayed
    const ok = await apiJson("/api/apple", { identityToken: await appleToken({ sub: "x1", nonce: hashed }), nonce });
    expect(ok.status).toBe(200);
    expect((await apiJson("/api/apple", { identityToken: await appleToken({ sub: "x1", nonce: hashed }), nonce })).status).toBe(400);
    // unsigned callers still get nothing
    expect((await apiGet("/api/sync?since=0")).status).toBe(401);
  });

  it("picks handles that fit and are free", async () => {
    expect(await freeHandle(env.NOTES, "Cassidy")).toBe("BUS::CASSIDY");
    expect(await freeHandle(env.NOTES, "Jean-Luc O'Brien-Smythe!!")).toBe("BUS::JEANLUCOBRIE");
    expect(await freeHandle(env.NOTES, null)).toMatch(/^BUS::[A-Z]{4}$/);
    expect(await freeHandle(env.NOTES, "A")).toMatch(/^BUS::[A-Z]{4}$/);
    await signUp(new SoftAuthenticator(), "bus", "taken");
    expect(await freeHandle(env.NOTES, "taken")).toBe("BUS::TAKEN2");
  });

  it("a passkey head can still sign in and sees no Apple line", async () => {
    const { cookie } = await signUp(new SoftAuthenticator(), "phish", "keyhead");
    const html = await (await get("/me", cookie)).text();
    expect(html).not.toContain("Signed in with Apple");
    expect(html).not.toContain("Keep this handle");
  });
});
