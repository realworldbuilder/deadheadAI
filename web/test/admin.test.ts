import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { SoftAuthenticator } from "./softauth";
import { form, get, signUp } from "./helpers";

describe("the back room", () => {
  it("is a 404 to everyone but the admin, who can freeze, pull and erase", async () => {
    const plain = await signUp(new SoftAuthenticator(), "phish", "someone");
    expect((await get("/admin")).status).toBe(404);
    expect((await get("/admin", plain.cookie)).status).toBe(404);
    // the ADMIN_HANDLES var (RDVAX::HUSSEY in wrangler.toml) needs the reserved node; sign up with role=admin instead
    const boss = await signUp(new SoftAuthenticator(), "nacad2", "boss");
    await env.NOTES.prepare("UPDATE users SET role='admin' WHERE handle='NACAD2::BOSS'").run();
    const home = await get("/admin", boss.cookie);
    expect(home.status).toBe(200);
    expect(await home.text()).toContain("Heads");
    // a note from the plain head, pulled by the admin
    await form("/shows/1977-05-08/notes", { body: "First!" }, plain.cookie);
    const heads = await (await get("/admin/heads?q=PHISH", boss.cookie)).text();
    expect(heads).toContain("PHISH::SOMEONE");
    const notes = await (await get("/admin/notes", boss.cookie)).text();
    expect(notes).toContain("First!");
    const pull = await form("/admin/notes/1.1/delete", {}, boss.cookie);
    expect(pull.status).toBe(303);
    expect(await (await get("/notes/1.1")).text()).toContain("Note pulled by the admin.");
    // freeze: the head's session stops working; thaw brings it back
    await form("/admin/heads/PHISH::SOMEONE/disable", {}, boss.cookie);
    expect((await get("/me", plain.cookie)).status).toBe(303);
    await form("/admin/heads/PHISH::SOMEONE/enable", {}, boss.cookie);
    // erase needs the handle typed
    const half = await form("/admin/heads/PHISH::SOMEONE/delete", { confirm_handle: "nope" }, boss.cookie);
    expect(half.headers.get("location")).toContain("Type%20the%20handle");
    await form("/admin/heads/PHISH::SOMEONE/delete", { confirm_handle: "phish::someone" }, boss.cookie);
    const left = await env.NOTES.prepare("SELECT COUNT(*) AS n FROM users WHERE handle='PHISH::SOMEONE'").first<{ n: number }>();
    expect(left!.n).toBe(0);
    const tomb = await env.NOTES.prepare("SELECT deleted_by, handle FROM notes WHERE topic_id=1 AND reply_no=1").first<{ deleted_by: string; handle: string | null }>();
    expect(tomb!.handle).toBeNull();
    // the admin's own page still works
    expect((await get("/admin", boss.cookie)).status).toBe(200);
  });
});
