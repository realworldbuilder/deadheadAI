import { SELF, env } from "cloudflare:test";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const realFetch = globalThis.fetch;
beforeAll(() => {
  // Tests and the worker share one isolate, so stubbing fetch here stands in for archive.org.
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    if (url.startsWith("https://archive.org/metadata/")) {
      return new Response(JSON.stringify({
        metadata: { venue: "Barton Hall", date: "1977-05-08" },
        files: [{ name: "gd77-05-08d1t01.mp3", format: "VBR MP3", title: "New Minglewood Blues", length: "5:10", track: "01" }],
        reviews: [{ reviewtitle: "The one", reviewbody: "Jerry CRANKED.", stars: "5", reviewer: "sparkyjoe", reviewdate: "2009-03-02 10:00:00" }],
      }), { headers: { "content-type": "application/json" } });
    }
    return realFetch(input, init);
  }) as typeof fetch;
});
afterAll(() => { globalThis.fetch = realFetch; });

const get = (path: string) => SELF.fetch(`https://nethead.test${path}`);

describe("the fixture catalog", () => {
  it("has Cornell", async () => {
    const row = await env.CATALOG.prepare("SELECT venue FROM shows WHERE show_id='1977-05-08'").first<{ venue: string }>();
    expect(row?.venue).toContain("Barton Hall");
  });
  it("finds 5-8-77 every way heads write it", async () => {
    for (const qtext of ['"5-8-77"*', '"5/8/77"*', '"may"* "8"* "1977"*', '"cornell"*']) {
      const hit = await env.CATALOG.prepare("SELECT s.show_id FROM show_fts JOIN shows s ON s.rowid = show_fts.rowid WHERE show_fts MATCH ? ORDER BY rank LIMIT 3").bind(qtext).all<{ show_id: string }>();
      expect(hit.results.map((r) => r.show_id)).toContain("1977-05-08");
    }
  });
});

describe("pages", () => {
  it("the front page", async () => {
    const res = await get("/");
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain("RDVAX::GRATEFUL");
    expect(html).toContain("Tonight");
    expect(html).toContain("Get on the Bus");
  });
  it("the topic page for Cornell", async () => {
    const res = await get("/shows/1977-05-08");
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain("5/8/77 · Barton Hall (Cornell U) · Ithaca, NY");
    expect(html).toContain("Scarlet Begonias");
    const chicago = await (await get("/shows/1995-07-09")).text();
    expect(chicago).toContain('class="segue"');
    expect(html).toContain("Spin the best tape");
    expect(html).toContain("gd77-05-08.sbd.hicks.4982.sbeok.shnf");
    expect(html).toContain("Write a Note");
    expect(html).toContain("No notes on this show yet");
    expect(html).toContain('href="/shows/1977-05-08.txt"');
  });
  it("the setlist as plain text", async () => {
    const res = await get("/shows/1977-05-08.txt");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/plain");
    const txt = await res.text();
    expect(txt.startsWith("Grateful Dead\n5/8/77")).toBe(true);
    expect(txt).toContain("Scarlet Begonias");
    const chicago = await (await get("/shows/1995-07-09.txt")).text();
    expect(chicago).toMatch(/ >\n/);
  });
  it("a tape page", async () => {
    const res = await get("/shows/1977-05-08/gd77-05-08.sbd.hicks.4982.sbeok.shnf");
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain("Tracks");
    expect(html).toContain("Other Tapes");
    expect(html).toContain('data-spin="gd77-05-08.sbd.hicks.4982.sbeok.shnf"');
    expect(html).toContain("Jerry CRANKED.");
    expect(html).toContain("sparkyjoe");
  });
  it("a night the Dead didn't play", async () => {
    const res = await get("/shows/1977-05-09");
    expect(res.status).toBe(404);
    expect(await res.text()).toContain("play 5/9/77.");
  });
  it("years and a year", async () => {
    expect((await get("/years")).status).toBe(200);
    const res = await get("/years/1977");
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("Barton Hall");
    expect((await get("/years/2001")).status).toBe(404);
  });
  it("on this day", async () => {
    const res = await get("/on-this-day?d=05-08");
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("5/8/77");
  });
  it("search direct hits", async () => {
    const res = await get("/search?q=5-8-77");
    const html = await res.text();
    expect(html).toContain("Direct hit");
    expect(html).toContain("/shows/1977-05-08");
    const song = await (await get("/search?q=dark+star")).text();
    expect(song).toContain("Tune:");
  });
  it("songs", async () => {
    expect((await get("/songs")).status).toBe(200);
    const res = await get("/songs/dark-star");
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("Dark Star");
  });
  it("404 in voice", async () => {
    const res = await get("/nowhere");
    expect(res.status).toBe(404);
    expect(await res.text()).toContain("Nothing here.");
  });
  it("static assets are served", async () => {
    if (!env.ASSETS) return;
    const res = await get("/style.css");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/css");
  });
});
