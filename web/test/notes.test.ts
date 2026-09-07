import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { SoftAuthenticator } from "./softauth";
import { form, get, signUp } from "./helpers";
import { cleanBody } from "../src/notes/numbering";

describe("note bodies", () => {
  it("are trimmed, Unix-newlined, and capped", () => {
    expect(cleanBody("  Scarlet > Fire was HOT \r\n\r\nsecond line  ")).toEqual({ body: "Scarlet > Fire was HOT\n\nsecond line" });
    expect("error" in cleanBody("   ")).toBe(true);
    expect("error" in cleanBody("x".repeat(4001))).toBe(true);
  });
});

describe("the conference", () => {
  it("numbers notes densely, keeps numbers across pulls, links dates and handles", async () => {
    const auth = new SoftAuthenticator();
    const { cookie, handle } = await signUp(auth, "phish", "hussey");
    const auth2 = new SoftAuthenticator();
    const other = await signUp(auth2, "nacad2", "siegel", "1994");

    // first note mints topic 1, reply 1
    const r1 = await form("/shows/1977-05-08/notes", { body: "Spun the Hicks board. Scarlet > Fire is the whole reason. Saw NACAD2::SIEGEL there on 5/8/77." }, cookie);
    expect(r1.status).toBe(303);
    expect(r1.headers.get("location")).toBe("/notes/1.1");
    // burst limit: a second note twenty seconds later, not now
    const burst = await form("/shows/1977-05-08/notes", { body: "again" }, cookie);
    expect(burst.status).toBe(429);
    // back-date the first note so the next one goes through
    await env.NOTES.prepare("UPDATE notes SET created_at=? WHERE id=1").bind(new Date(Date.now() - 60000).toISOString()).run();
    const r2 = await form("/shows/1977-05-08/notes", { body: "And the Morning Dew." }, other.cookie);
    expect(r2.headers.get("location")).toBe("/notes/1.2");
    const r3 = await form("/shows/1972-05-04/notes", { body: "Paris. The Dark Star." }, other.cookie);
    expect(r3.status, await r3.clone().text()).toBe(429);
    await env.NOTES.prepare("UPDATE notes SET created_at=? WHERE id=2").bind(new Date(Date.now() - 60000).toISOString()).run();
    const r3b = await form("/shows/1972-05-04/notes", { body: "Paris. The Dark Star." }, other.cookie);
    expect(r3b.headers.get("location")).toBe("/notes/2.1");

    // the topic page shows them, numbered, with the links
    const topic = await (await get("/shows/1977-05-08")).text();
    expect(topic).toContain("GRATEFUL <a href=\"/notes/1.1\">1.1</a>");
    expect(topic).toContain("Scarlet &gt; Fire");
    expect(topic).toContain('<a href="/heads/NACAD2::SIEGEL">NACAD2::SIEGEL</a>');
    expect(topic).toContain('<a href="/shows/1977-05-08">5/8/77</a>');
    expect(topic).toContain("Topic 1 · 2 notes");

    // one note, with prev/next
    const single = await (await get("/notes/1.2")).text();
    expect(single).toContain("Note 1.2");
    expect(single).toContain("← 1.1");
    // .0 is the show
    const zero = await get("/notes/1.0");
    expect(zero.status).toBe(302);
    expect(zero.headers.get("location")).toBe("/shows/1977-05-08");

    // recent notes, newest first, marks unseen for a signed-in head and moves the high-water mark
    const recent = await (await get("/notes", cookie)).text();
    expect(recent.indexOf("2.1")).toBeLessThan(recent.indexOf("1.2"));
    expect(recent).toContain('class="unseen"');

    // the author can edit inside fifteen minutes, nobody else can
    const edit = await form("/notes/1.2/edit", { body: "And the Morning Dew. Jerry CRANKED." }, other.cookie);
    expect(edit.status).toBe(303);
    expect(await (await get("/notes/1.2")).text()).toContain("Jerry CRANKED");
    const notMine = await form("/notes/1.2/edit", { body: "hijack" }, cookie);
    expect(notMine.status).toBe(404);
    await env.NOTES.prepare("UPDATE notes SET created_at=? WHERE id=2").bind(new Date(Date.now() - 20 * 60000).toISOString()).run();
    const late = await form("/notes/1.2/edit", { body: "too late" }, other.cookie);
    expect(late.status).toBe(403);

    // pulling keeps the number; the count drops
    const pull = await form("/notes/1.1/delete", {}, cookie);
    expect(pull.status).toBe(303);
    const pulled = await (await get("/notes/1.1")).text();
    expect(pulled).toContain("Note pulled by its author.");
    const count = await env.NOTES.prepare("SELECT note_count FROM topics WHERE id=1").first<{ note_count: number }>();
    expect(count?.note_count).toBe(1);
    // the next note on the topic is 1.3, not 1.1 again
    await env.NOTES.prepare("UPDATE notes SET created_at=? WHERE user_id=(SELECT id FROM users WHERE handle=?)").bind(new Date(Date.now() - 60000).toISOString(), handle).run();
    const r4 = await form("/shows/1977-05-08/notes", { body: "Row Jimmy too." }, cookie);
    expect(r4.headers.get("location")).toBe("/notes/1.3");

    // the head page lists their notes and the bus line
    const page = await (await get("/heads/NACAD2::SIEGEL")).text();
    expect(page).toContain("On the bus since &#39;94");
    expect(page).toContain("2.1");
    expect((await get("/heads/nacad2::siegel")).status).toBe(301);
    expect((await get("/heads/NOBODY::HERE")).status).toBe(404);
    const txt = await (await get("/heads/NACAD2::SIEGEL.txt")).text();
    expect(txt.startsWith("NACAD2::SIEGEL tape list\nOn the bus since '94")).toBe(true);
    expect(txt).toContain("Nothing public on the shelf.");

    // signed out heads can't post
    const anon = await form("/shows/1977-05-08/notes", { body: "hi" });
    expect(anon.status).toBe(303);
    expect(anon.headers.get("location")).toContain("/signin");
  });

  it("enforces the daily thirty", async () => {
    const auth = new SoftAuthenticator();
    const { cookie } = await signUp(auth, "cscma", "m_peckar");
    const user = await env.NOTES.prepare("SELECT id FROM users WHERE handle='CSCMA::M_PECKAR'").first<{ id: string }>();
    await env.NOTES.prepare("INSERT OR IGNORE INTO topics (show_id, title, note_count, created_at) VALUES ('1969-02-27','x',0,?)").bind(new Date().toISOString()).run();
    const topic = await env.NOTES.prepare("SELECT id FROM topics WHERE show_id='1969-02-27'").first<{ id: number }>();
    const stmts = [];
    for (let i = 1; i <= 30; i++) {
      stmts.push(env.NOTES.prepare("INSERT INTO notes (topic_id, reply_no, user_id, handle, body, created_at) SELECT ?, COALESCE(MAX(reply_no),0)+1, ?, ?, ?, ? FROM notes WHERE topic_id=?")
        .bind(topic!.id, user!.id, "CSCMA::M_PECKAR", "n" + i, new Date(Date.now() - 3600000 - i * 1000).toISOString(), topic!.id));
    }
    for (const st of stmts) await st.run();
    const res = await form("/shows/1969-02-27/notes", { body: "thirty-one" }, cookie);
    expect(res.status).toBe(429);
    expect(await res.text()).toContain("Thirty notes in a day");
  });
});
