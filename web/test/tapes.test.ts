import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { SoftAuthenticator } from "./softauth";
import { form, get, signUp, ORIGIN } from "./helpers";

describe("tape lists", () => {
  it("shelves a show, orders it, hides private shelves, tosses it", async () => {
    const auth = new SoftAuthenticator();
    const { cookie, handle } = await signUp(auth, "phish", "shelver");
    const other = await signUp(new SoftAuthenticator(), "nacad2", "reader");

    // "A new shelf…" from the topic page lands on the new-shelf form, which shelves it
    const r0 = await form("/me/shelves/add", { show_id: "1977-05-08", shelf_id: "new" }, cookie);
    expect(r0.headers.get("location")).toBe("/me/shelves?show=1977-05-08");
    const r1 = await form("/me/shelves", { name: "Top Shelf", show_id: "1977-05-08" }, cookie);
    expect(r1.headers.get("location")).toBe("/shows/1977-05-08?ok=shelved");
    const shelf = await env.NOTES.prepare("SELECT id, seq FROM shelves WHERE user_id=(SELECT id FROM users WHERE handle=?)").bind(handle).first<{ id: string; seq: number }>();
    expect(shelf!.id).toMatch(/^[0-9A-F-]{36}$/);
    const item = await env.NOTES.prepare("SELECT display_name, show_identifier, show_date, seq FROM shelf_items WHERE shelf_id=?").bind(shelf!.id).first<{ display_name: string; show_identifier: string; show_date: string; seq: number }>();
    expect(item!.display_name).toBe("5/8/77 Barton Hall (Cornell U)");
    expect(item!.show_identifier).toBe("gd77-05-08.sbd.hicks.4982.sbeok.shnf");
    expect(item!.seq).toBeGreaterThanOrEqual(shelf!.seq);

    // shelve two more, once twice
    expect((await form("/me/shelves/add", { show_id: "1972-05-04", shelf_id: shelf!.id }, cookie)).headers.get("location")).toBe("/shows/1972-05-04?ok=shelved");
    expect((await form("/me/shelves/add", { show_id: "1972-05-04", shelf_id: shelf!.id }, cookie)).headers.get("location")).toBe("/shows/1972-05-04?ok=already");
    await form("/me/shelves/add", { show_id: "1969-02-27", shelf_id: shelf!.id }, cookie);
    const topic = await (await get("/shows/1977-05-08?ok=shelved", cookie)).text();
    expect(topic).toContain("Shelved.");
    expect(topic).toContain("Top Shelf");

    // the public page, in order, with the txt
    const pub = await (await get(`/heads/${handle}/shelves/${shelf!.id}`)).text();
    expect(pub.indexOf("5/8/77")).toBeLessThan(pub.indexOf("5/4/72"));
    expect(pub.indexOf("5/4/72")).toBeLessThan(pub.indexOf("2/27/69"));
    const txt = await (await get(`/heads/${handle}.txt`)).text();
    expect(txt).toContain("Top Shelf  (3 tapes)");
    expect(txt).toContain("gd77-05-08.sbd.hicks.4982.sbeok.shnf");

    // move the last one up
    const items = await env.NOTES.prepare("SELECT id FROM shelf_items WHERE shelf_id=? AND deleted_at IS NULL ORDER BY sort_index").bind(shelf!.id).all<{ id: string }>();
    await form(`/me/shelves/${shelf!.id}/items/${items.results[2]!.id}/move`, { dir: "up" }, cookie);
    const after = await env.NOTES.prepare("SELECT id FROM shelf_items WHERE shelf_id=? AND deleted_at IS NULL ORDER BY sort_index").bind(shelf!.id).all<{ id: string }>();
    expect(after.results.map((r) => r.id)).toEqual([items.results[0]!.id, items.results[2]!.id, items.results[1]!.id]);

    // take one off: soft delete
    await form(`/me/shelves/${shelf!.id}/items/${items.results[1]!.id}/delete`, {}, cookie);
    const left = await env.NOTES.prepare("SELECT COUNT(*) AS n FROM shelf_items WHERE shelf_id=? AND deleted_at IS NULL").bind(shelf!.id).first<{ n: number }>();
    expect(left!.n).toBe(2);
    const gone = await env.NOTES.prepare("SELECT deleted_at FROM shelf_items WHERE id=?").bind(items.results[1]!.id).first<{ deleted_at: string | null }>();
    expect(gone!.deleted_at).not.toBeNull();

    // private: 404 for others, fine for the owner, gone from the index
    await form(`/me/shelves/${shelf!.id}`, { name: "Top Shelf", blurb: "the good stuff", is_private: "1" }, cookie);
    expect((await get(`/heads/${handle}/shelves/${shelf!.id}`, other.cookie)).status).toBe(404);
    expect((await get(`/heads/${handle}/shelves/${shelf!.id}`, cookie)).status).toBe(200);
    expect(await (await get("/tapelists")).text()).not.toContain("Top Shelf");
    expect(await (await get(`/heads/${handle}.txt`)).text()).toContain("Nothing public on the shelf.");
    // someone else can't edit it
    expect((await form(`/me/shelves/${shelf!.id}`, { name: "hijacked" }, other.cookie)).status).toBe(404);

    // toss it
    const toss = await (await get(`/me/shelves/${shelf!.id}/toss`, cookie)).text();
    expect(toss).toContain("Toss “Top Shelf”?");
    await form(`/me/shelves/${shelf!.id}/delete`, {}, cookie);
    expect((await get(`/me/shelves/${shelf!.id}`, cookie)).status).toBe(404);
    const seqs = await env.NOTES.prepare("SELECT seq FROM shelf_items WHERE shelf_id=? ORDER BY seq").bind(shelf!.id).all<{ seq: number }>();
    expect(seqs.results.length).toBe(3);
  });

  it("puts a tune on a mix tape and the deck can play it", async () => {
    const auth = new SoftAuthenticator();
    const { cookie, handle } = await signUp(auth, "cscma", "mixer");
    const r0 = await form("/me/mixtapes/add", { identifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", file_name: "gd77-05-08d2t01.mp3", mixtape_id: "new" }, cookie);
    expect(r0.headers.get("location")).toContain("/me/mixtapes?identifier=");
    const tracks = await env.CATALOG.prepare("SELECT tracks_json FROM recording_tracks WHERE identifier='gd77-05-08.sbd.hicks.4982.sbeok.shnf'").first<{ tracks_json: string }>();
    const scarlet = (JSON.parse(tracks!.tracks_json) as [string, number, string][]).find((t) => /scarlet/i.test(t[0]))!;
    const r1 = await form("/me/mixtapes", { name: "Sunday Morning", identifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", file_name: scarlet[2] }, cookie);
    expect(r1.headers.get("location")).toMatch(/\/me\/mixtapes\/[0-9A-F-]{36}\?ok=added/);
    const id = /\/me\/mixtapes\/([0-9A-F-]{36})/.exec(r1.headers.get("location")!)![1]!;
    const row = await env.NOTES.prepare("SELECT track_title, song_key, show_date_string, show_display_name, duration_seconds FROM mixtape_items WHERE mixtape_id=?").bind(id).first<{ track_title: string; song_key: string; show_date_string: string; show_display_name: string; duration_seconds: number }>();
    expect(row!.song_key).toContain("scarlet begonias");
    expect(row!.show_date_string).toBe("1977-05-08");
    expect(row!.show_display_name).toBe("5/8/77 Barton Hall (Cornell U)");
    expect(row!.duration_seconds).toBeGreaterThan(0);
    // same tune twice is a no-op
    const again = await form("/me/mixtapes/add", { identifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", file_name: scarlet[2], mixtape_id: id }, cookie);
    expect(again.headers.get("location")).toContain("ok=already");
    // the deck's feed
    const feed = await SELF.fetch(`${ORIGIN}/deck/mixtapes/${id}`);
    expect(feed.status).toBe(200);
    const j = await feed.json<{ title: string; tracks: { url: string; pretty: string }[] }>();
    expect(j.title).toBe("Sunday Morning");
    expect(j.tracks[0]!.url).toContain("https://archive.org/download/gd77-05-08.sbd.hicks.4982.sbeok.shnf/");
    expect(j.tracks[0]!.pretty).toBe("5/8/77");
    // public page and the index
    expect(await (await get(`/heads/${handle}/mixtapes/${id}`)).text()).toContain("Scarlet Begonias");
    expect(await (await get("/tapelists")).text()).toContain("Sunday Morning");
  });

  it("keeps a journal, privately", async () => {
    const auth = new SoftAuthenticator();
    const { cookie } = await signUp(auth, "cslall", "writer");
    const bad = await form("/me/journal", { show: "nowhere", body: "x" }, cookie);
    expect(bad.status).toBe(400);
    const r = await form("/me/journal", { show: "5/8/77", body: "Drove up from Boston. Never the same.", mood: "hot" }, cookie);
    expect(r.status).toBe(303);
    const page = await (await get("/me/journal", cookie)).text();
    expect(page).toContain("Never the same.");
    expect(page).toContain("5/8/77 Barton Hall (Cornell U)");
    const entry = await env.NOTES.prepare("SELECT id, show_identifier FROM journal_entries").first<{ id: string; show_identifier: string }>();
    expect(entry!.show_identifier).toBe("gd77-05-08.sbd.hicks.4982.sbeok.shnf");
    await form(`/me/journal/${entry!.id}`, { body: "Drove up from Boston. Never the same. Row Jimmy.", mood: "" }, cookie);
    expect(await (await get("/me/journal", cookie)).text()).toContain("Row Jimmy.");
    await form(`/me/journal/${entry!.id}/delete`, {}, cookie);
    expect(await (await get("/me/journal", cookie)).text()).toContain("Nothing in the journal yet.");
    // the journal isn't on the head page
    expect(await (await get("/heads/CSLALL::WRITER")).text()).not.toContain("Boston");
  });
});
