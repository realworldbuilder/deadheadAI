import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { SoftAuthenticator } from "./softauth";
import { form, get, json, signUp } from "./helpers";
import { purge } from "../src/cron";

describe("trees", () => {
  it("start one, get on it, see what turns up, close it", async () => {
    const owner = await signUp(new SoftAuthenticator(), "phish", "treeowner");
    const member = await signUp(new SoftAuthenticator(), "nacad2", "treemember");
    await form("/me/shelves", { name: "Cornell Tree", show_id: "1977-05-08" }, owner.cookie);
    const shelf = await env.NOTES.prepare("SELECT id FROM shelves WHERE name='Cornell Tree'").first<{ id: string }>();
    // start the tree
    const start = await form(`/me/shelves/${shelf!.id}/tree`, {}, owner.cookie);
    expect(start.status).toBe(303);
    const treeId = start.headers.get("location")!.split("/").pop()!;
    // starting again lands on the same tree
    expect((await form(`/me/shelves/${shelf!.id}/tree`, {}, owner.cookie)).headers.get("location")).toBe(`/trees/${treeId}`);
    const page = await (await get(`/trees/${treeId}`)).text();
    expect(page).toContain("Cornell Tree");
    expect(page).toContain("started by");
    expect(page).toContain("Sign in");
    // the member gets on
    const join = await form(`/trees/${treeId}/join`, {}, member.cookie);
    expect(join.status).toBe(303);
    expect(await (await get(`/trees/${treeId}`, member.cookie)).text()).toContain("Get off the tree");
    // nothing new yet; the owner adds a tape; now it's in the feed
    expect(await (await get("/me/tree", member.cookie)).text()).toContain("Nothing new since you got on");
    await new Promise((r) => setTimeout(r, 5));
    await form("/me/shelves/add", { show_id: "1972-05-04", shelf_id: shelf!.id }, owner.cookie);
    const feed = await (await get("/me/tree", member.cookie)).text();
    expect(feed).toContain("5/4/72");
    expect(feed).not.toContain("5/8/77 ");
    // the owner's own feed is empty (they're not a member of their own tree)
    expect(await (await get("/me/tree", owner.cookie)).text()).toContain("not on any trees");
    // it shows on the member's page and the index
    expect(await (await get("/heads/NACAD2::TREEMEMBER")).text()).toContain("Cornell Tree");
    expect(await (await get("/tapelists")).text()).toContain("Cornell Tree");
    // making the shelf private closes the tree
    await form(`/me/shelves/${shelf!.id}`, { name: "Cornell Tree", is_private: "1" }, owner.cookie);
    expect((await get(`/trees/${treeId}`)).status).toBe(404);
    // public again + start again reopens the same tree row
    await form(`/me/shelves/${shelf!.id}`, { name: "Cornell Tree" }, owner.cookie);
    expect((await form(`/me/shelves/${shelf!.id}/tree`, {}, owner.cookie)).headers.get("location")).toBe(`/trees/${treeId}`);
    // leave, then the owner closes it
    await form(`/trees/${treeId}/leave`, {}, member.cookie);
    expect(await (await get(`/trees/${treeId}`, member.cookie)).text()).toContain("Get on the tree");
    expect((await form(`/trees/${treeId}/close`, {}, member.cookie)).status).toBe(404);
    expect((await form(`/trees/${treeId}/close`, {}, owner.cookie)).status).toBe(303);
    expect((await get(`/trees/${treeId}`)).status).toBe(404);
  });
});

describe("the lot", () => {
  it("shows who's spinning, coalesces a tape, honours the opt-out, purges", async () => {
    const auth = new SoftAuthenticator();
    const { cookie, handle } = await signUp(auth, "cscma", "spinner");
    const spin = (body: unknown, ck = cookie) => json("/deck/spin", body, ck);
    expect((await spin({ identifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", showId: "1977-05-08", trackTitle: "Scarlet Begonias" })).status).toBe(204);
    let lotPage = await (await get("/lot")).text();
    expect(lotPage).toContain(handle);
    expect(lotPage).toContain("Scarlet Begonias");
    expect(lotPage).toContain("Spin along");
    // ten seconds of quiet before the next write; back-date and switch tunes on the same tape → one row
    await env.NOTES.prepare("UPDATE spins SET updated_at=?").bind(new Date(Date.now() - 30000).toISOString()).run();
    await spin({ identifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", showId: "1977-05-08", trackTitle: "Fire on the Mountain" });
    let rows = await env.NOTES.prepare("SELECT track_title FROM spins").all<{ track_title: string }>();
    expect(rows.results.map((r) => r.track_title)).toEqual(["Fire on the Mountain"]);
    // a different tape replaces the row
    await env.NOTES.prepare("UPDATE spins SET updated_at=?").bind(new Date(Date.now() - 30000).toISOString()).run();
    await spin({ identifier: "gd1972-05-04.sbd.miller.77294.sbeok.flac16", showId: "1972-05-04", trackTitle: "Dark Star" });
    rows = await env.NOTES.prepare("SELECT track_title FROM spins").all<{ track_title: string }>();
    expect(rows.results.map((r) => r.track_title)).toEqual(["Dark Star"]);
    // twenty minutes on, it's "earlier tonight"; the front page drops it
    await env.NOTES.prepare("UPDATE spins SET updated_at=?").bind(new Date(Date.now() - 25 * 60000).toISOString()).run();
    lotPage = await (await get("/lot")).text();
    expect(lotPage).toContain("Earlier Tonight");
    expect(lotPage).toContain("empty right now");
    expect(await (await get("/")).text()).toContain("Spin a tape and you");
    // the head page shows it while it's fresh
    await env.NOTES.prepare("UPDATE spins SET updated_at=?").bind(new Date().toISOString()).run();
    expect(await (await get(`/heads/${handle}`)).text()).toContain("Spinning");
    // stopped clears it
    await spin({ stopped: true });
    expect((await env.NOTES.prepare("SELECT COUNT(*) AS n FROM spins").first<{ n: number }>())!.n).toBe(0);
    // opt out: nothing written, and the row is gone
    await form("/me", { first_show: "", share_spins: "" }, cookie);
    await spin({ identifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", showId: "1977-05-08", trackTitle: "Deal" });
    expect((await env.NOTES.prepare("SELECT COUNT(*) AS n FROM spins").first<{ n: number }>())!.n).toBe(0);
    // signed out: 204 and nothing
    expect((await json("/deck/spin", { identifier: "x", trackTitle: "y" })).status).toBe(204);
    // the purge drops day-old spins and dead ceremonies
    await form("/me", { first_show: "", share_spins: "1" }, cookie);
    await spin({ identifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", showId: "1977-05-08", trackTitle: "Deal" });
    await env.NOTES.prepare("UPDATE spins SET updated_at=?").bind(new Date(Date.now() - 25 * 3600000).toISOString()).run();
    await env.NOTES.prepare("INSERT INTO ceremonies (id, kind, challenge, created_at, expires_at) VALUES ('old','signin','c',?,?)").bind("2020-01-01T00:00:00Z", "2020-01-01T00:05:00Z").run();
    await purge(env);
    expect((await env.NOTES.prepare("SELECT COUNT(*) AS n FROM spins").first<{ n: number }>())!.n).toBe(0);
    expect((await env.NOTES.prepare("SELECT COUNT(*) AS n FROM ceremonies WHERE id='old'").first<{ n: number }>())!.n).toBe(0);
  });
});
