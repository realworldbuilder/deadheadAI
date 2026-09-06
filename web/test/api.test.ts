import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { SoftAuthenticator } from "./softauth";
import { ORIGIN, form, get, signUp } from "./helpers";
import { normalizeCode } from "../src/api/routes";

const apiJson = (path: string, body: unknown, token?: string, method = "POST") => SELF.fetch(ORIGIN + path, {
  method, body: method === "GET" ? undefined : JSON.stringify(body),
  headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
});
const apiGet = (path: string, token?: string) => SELF.fetch(ORIGIN + path, { headers: token ? { authorization: `Bearer ${token}` } : {} });

describe("the phone's side", () => {
  it("pairs with a code, syncs both ways, spins, reads notes, signs out", async () => {
    const auth = new SoftAuthenticator();
    const { cookie, handle } = await signUp(auth, "shakedown", "og", "11/18/87");
    // a code from the head's page
    const page = await form("/me/pair", {}, cookie);
    expect(page.status).toBe(200);
    const code = /class="code"[^>]*>([^<]+)</.exec(await page.text())![1]!;
    expect(normalizeCode(code)).toHaveLength(6);
    // wrong code, then the right one, then the same code again (one use)
    expect((await apiJson("/api/pair", { code: "XXX-XXX", device: "iPhone" })).status).toBe(400);
    const paired = await apiJson("/api/pair", { code: code.toLowerCase(), device: "iPhone 16 Pro" });
    expect(paired.status, await paired.clone().text()).toBe(200);
    const { token, head } = await paired.json<{ token: string; head: { handle: string; firstShow: string } }>();
    expect(head.handle).toBe(handle);
    expect(head.firstShow).toBe("1987-11-18");
    expect((await apiJson("/api/pair", { code })).status).toBe(400);
    // me
    const me = await apiGet("/api/me", token);
    expect(me.status).toBe(200);
    expect((await me.json<{ head: { handle: string } }>()).head.handle).toBe(handle);
    expect((await apiGet("/api/me")).status).toBe(401);
    expect((await apiGet("/api/me", "nope")).status).toBe(401);

    // the phone pushes a shelf with an item, and a journal entry
    const shelfId = crypto.randomUUID().toUpperCase();
    const itemId = crypto.randomUUID().toUpperCase();
    const entryId = crypto.randomUUID().toUpperCase();
    const t0 = new Date(Date.now() - 60000).toISOString();
    const push = await apiJson("/api/sync", {
      shelves: [{ id: shelfId, name: "Phone Shelf", blurb: "", iconName: "heart.fill", isPrivate: false, createdAt: t0, updatedAt: t0, deletedAt: null }],
      shelfItems: [{ id: itemId, shelfId, showIdentifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", showId: null, showDate: "1977-05-08", displayName: "5/8/77 Barton Hall", sortIndex: 0, addedAt: t0, updatedAt: t0, deletedAt: null }],
      journalEntries: [{ id: entryId, showIdentifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", showId: null, showDate: "1977-05-08", showDisplayName: "5/8/77 Barton Hall", body: "From the phone.", mood: null, createdAt: t0, updatedAt: t0, deletedAt: null }],
    }, token);
    expect(push.status, await push.clone().text()).toBe(200);
    const pushed = await push.json<{ cursor: number; accepted: number; skipped: number }>();
    expect(pushed.accepted).toBe(3);
    // the site shows it, and filled in the catalog show id
    expect(await (await get(`/heads/${handle}`)).text()).toContain("Phone Shelf");
    const row = await env.NOTES.prepare("SELECT show_id FROM shelf_items WHERE id=?").bind(itemId).first<{ show_id: string }>();
    expect(row!.show_id).toBe("1977-05-08");
    // an item for a shelf nobody has is skipped, not an error
    const orphan = await apiJson("/api/sync", { shelfItems: [{ id: crypto.randomUUID().toUpperCase(), shelfId: crypto.randomUUID().toUpperCase(), showIdentifier: "x", showId: null, showDate: null, displayName: "x", sortIndex: 0, addedAt: t0, updatedAt: t0, deletedAt: null }] }, token);
    expect((await orphan.json<{ skipped: number }>()).skipped).toBe(1);

    // the site makes a mix tape; the phone pulls it
    await form("/me/mixtapes", { name: "Site Tape" }, cookie);
    const pull = await apiGet(`/api/sync?since=${pushed.cursor}`, token);
    expect(pull.status).toBe(200);
    const pulled = await pull.json<{ cursor: number; mixtapes: { name: string }[]; shelves: unknown[] }>();
    expect(pulled.mixtapes.map((m) => m.name)).toEqual(["Site Tape"]);
    expect(pulled.shelves.length).toBe(0);
    expect(pulled.cursor).toBeGreaterThan(pushed.cursor);
    // a full pull has everything
    const all = await (await apiGet("/api/sync?since=0", token)).json<{ shelves: { name: string }[]; journalEntries: { body: string }[] }>();
    expect(all.shelves.map((s) => s.name)).toContain("Phone Shelf");
    expect(all.journalEntries[0]!.body).toBe("From the phone.");

    // last writer wins: a stale rename loses, a fresh one wins
    const stale = await apiJson("/api/sync", { shelves: [{ id: shelfId, name: "Stale", blurb: "", iconName: "heart.fill", isPrivate: false, createdAt: t0, updatedAt: new Date(Date.now() - 120000).toISOString(), deletedAt: null }] }, token);
    expect((await stale.json<{ accepted: number }>()).accepted).toBe(0);
    const fresh = await apiJson("/api/sync", { shelves: [{ id: shelfId, name: "Fresh", blurb: "", iconName: "heart.fill", isPrivate: false, createdAt: t0, updatedAt: new Date(Date.now() - 30000).toISOString(), deletedAt: null }] }, token);
    expect((await fresh.json<{ accepted: number }>()).accepted).toBe(1);
    expect((await env.NOTES.prepare("SELECT name FROM shelves WHERE id=?").bind(shelfId).first<{ name: string }>())!.name).toBe("Fresh");
    // a clock an hour fast is clamped to five minutes ahead
    const clampId = crypto.randomUUID().toUpperCase();
    await apiJson("/api/sync", { shelves: [{ id: clampId, name: "Clock", blurb: "", iconName: "sparkles", isPrivate: false, createdAt: t0, updatedAt: new Date(Date.now() + 3600000).toISOString(), deletedAt: null }] }, token);
    const clocked = await env.NOTES.prepare("SELECT updated_at FROM shelves WHERE id=?").bind(clampId).first<{ updated_at: string }>();
    expect(new Date(clocked!.updated_at).getTime()).toBeLessThan(Date.now() + 6 * 60000);
    // a tombstone from the phone hides it on the site
    const gone = await apiJson("/api/sync", { shelves: [{ id: shelfId, name: "Fresh", blurb: "", iconName: "heart.fill", isPrivate: false, createdAt: t0, updatedAt: new Date().toISOString(), deletedAt: new Date().toISOString() }] }, token);
    expect((await gone.json<{ accepted: number }>()).accepted).toBe(1);
    expect(await (await get(`/heads/${handle}`)).text()).not.toContain("Fresh");
    // and comes back down as a tombstone
    const after = await (await apiGet(`/api/sync?since=${pulled.cursor}`, token)).json<{ shelves: { id: string; deletedAt: string | null }[] }>();
    expect(after.shelves.find((s) => s.id === shelfId)!.deletedAt).not.toBeNull();

    // the phone in the lot
    const spin = await apiJson("/api/spin", { identifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", showId: "1977-05-08", trackTitle: "Scarlet Begonias" }, token);
    expect(spin.status).toBe(204);
    expect(await (await get("/lot")).text()).toContain("Scarlet Begonias");

    // notes under a night, public, with a link to write one
    await form("/shows/1977-05-08/notes", { body: "Spun it on the porch." }, cookie);
    const notes = await (await apiGet("/api/notes/1977-05-08")).json<{ noteCount: number; notes: { handle: string; body: string; ref: string }[]; page: string }>();
    expect(notes.noteCount).toBe(1);
    expect(notes.notes[0]!.body).toBe("Spun it on the porch.");
    expect(notes.notes[0]!.handle).toBe(handle);
    expect(notes.page).toBe("/shows/1977-05-08");
    expect((await (await apiGet("/api/notes/1969-02-27")).json<{ noteCount: number }>()).noteCount).toBe(0);

    // sign the phone out
    expect((await apiJson("/api/signout", {}, token)).status).toBe(204);
    expect((await apiGet("/api/me", token)).status).toBe(401);
    // the site's session is untouched
    expect((await get("/me", cookie)).status).toBe(200);
  });
});
