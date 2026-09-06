/** Getting on the bus, signing in and out, getting back on, and the passkey list. */
import { Hono } from "hono";
import type { App } from "../env";
import { handleFromParts, parseHandle } from "./handles";
import { generateRecoveryCode, hashCode, verifyCode } from "./recovery";
import { authenticationOptions, beginCeremony, consumeCeremony, labelFor, passkeysFor, registrationOptions, verifyAuthentication, verifyRegistration, type PasskeyRow } from "./webauthn";
import { createSession, requireHead, revokeAll, revokeCurrent } from "./sessions";
import { requireSameOrigin } from "./csrf";
import { isoPlus, nowIso, uuid } from "../db/ids";
import { one, q, stmt } from "../db/notes";
import { parseHeadDate } from "../fmt";
import { Frame, render } from "../views/frame";
import { Bus, NewCode, Recover, RecoverPasskey, SignIn } from "../views/bus";
import { Passkeys } from "../views/me";
import { consumeNonce, findOrCreateAppleHead, mintNonce, verifyAppleIdentityToken } from "./apple";
import { appleAudiences } from "../api/routes";

export const auth = new Hono<App>();

/** D1 wants BLOBs as a plain ArrayBuffer, not a typed-array view. */
function blob(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

const NO_JS = "Passkeys need JavaScript to make the key. Turn it on for this page and try again.";

function safeNext(raw: string | undefined): string {
  if (!raw || !raw.startsWith("/") || raw.startsWith("//")) return "/me";
  return raw;
}

function firstShowValue(raw: string | undefined): string | null | { error: string } {
  const text = (raw ?? "").trim();
  if (!text) return null;
  const parsed = parseHeadDate(text);
  if (!parsed) return { error: "That date didn't parse. Try 5/8/77, or just a year." };
  const year = Number(parsed.slice(0, 4));
  if (year < 1965 || year > 1995) return { error: "The bus ran from '65 to '95. A date in there, or leave it blank." };
  return parsed;
}

// --- Get on the Bus ------------------------------------------------------

auth.get("/bus", (c) => {
  if (c.get("head")) return c.redirect("/me", 303);
  return c.html(render(<Frame title="Get on the Bus" crumb={["Get on the Bus"]} head={null} page="bus" bus appleClientId={c.env.APPLE_WEB_CLIENT_ID ?? null}><Bus /></Frame>));
});

auth.post("/bus", async (c) => {
  const form = await c.req.parseBody();
  return c.html(render(<Frame title="Get on the Bus" crumb={["Get on the Bus"]} head={null} page="bus" bus appleClientId={c.env.APPLE_WEB_CLIENT_ID ?? null}>
    <Bus node={String(form.node ?? "")} name={String(form.name ?? "")} firstShow={String(form.first_show ?? "")} error={NO_JS} />
  </Frame>), 400);
});

auth.post("/bus/options", requireSameOrigin, async (c) => {
  if (c.get("head")) return c.json({ error: "You're already on the bus." }, 409);
  const body = await c.req.json<{ node?: string; name?: string; first_show?: string }>().catch(() => null);
  if (!body) return c.json({ error: "Malformed request." }, 400);
  const parsed = handleFromParts(String(body.node ?? ""), String(body.name ?? ""));
  if ("error" in parsed) return c.json({ error: parsed.error, field: "name" }, 400);
  const firstShow = firstShowValue(body.first_show);
  if (firstShow && typeof firstShow === "object") return c.json({ error: firstShow.error, field: "first_show" }, 400);
  const taken = await one(c.env.NOTES, "SELECT 1 AS x FROM users WHERE handle=?", parsed.handle);
  if (taken) return c.json({ error: `${parsed.handle} is taken. Try another name, or another node.`, field: "name" }, 409);
  const userId = uuid();
  const options = await registrationOptions(c, { userId, handle: parsed.handle, exclude: [] });
  const ceremonyId = await beginCeremony(c.env.NOTES, "signup", null, options.challenge, { ...parsed, firstShow, userId });
  return c.json({ ceremonyId, options });
});

auth.post("/bus/verify", requireSameOrigin, async (c) => {
  const body = await c.req.json<{ ceremonyId?: string; credential?: any }>().catch(() => null);
  if (!body?.ceremonyId || !body.credential) return c.json({ error: "Malformed request." }, 400);
  const ceremony = await consumeCeremony(c.env.NOTES, body.ceremonyId, "signup");
  if (!ceremony) return c.json({ error: "That took too long. Start again." }, 400);
  const payload = JSON.parse(ceremony.payload_json ?? "{}") as { handle: string; node: string; name: string; firstShow: string | null; userId: string };
  let reg;
  try { reg = await verifyRegistration(c, body.credential, ceremony.challenge); } catch (e) { reg = null; }
  if (!reg) return c.json({ error: "That passkey didn't check out. Try again." }, 400);
  const taken = await one(c.env.NOTES, "SELECT 1 AS x FROM users WHERE handle=?", payload.handle);
  if (taken) return c.json({ error: `${payload.handle} got taken while you were making the key. Pick another.` }, 409);
  const code = generateRecoveryCode();
  const now = nowIso();
  const label = labelFor(c.req.header("user-agent") ?? "", body.credential.authenticatorAttachment);
  await c.env.NOTES.batch([
    stmt(c.env.NOTES,
      "INSERT INTO users (id, handle, node, name, first_show, role, share_spins, recovery_hash, recovery_rotated_at, created_at, updated_at) VALUES (?,?,?,?,?,'head',1,?,?,?,?)",
      payload.userId, payload.handle, payload.node, payload.name, payload.firstShow, await hashCode(code), now, now, now),
    stmt(c.env.NOTES,
      "INSERT INTO passkeys (id, user_id, public_key, counter, transports, device_type, backed_up, label, created_at) VALUES (?,?,?,?,?,?,?,?,?)",
      reg.id, payload.userId, blob(reg.publicKey), reg.counter, JSON.stringify(reg.transports), reg.deviceType, reg.backedUp ? 1 : 0, label, now),
  ]);
  await createSession(c, payload.userId);
  return c.json({ ok: true, handle: payload.handle, recoveryCode: code, next: "/me" });
});

// --- Sign in with Apple (the website) ----------------------------------------

auth.get("/auth/apple/nonce", requireSameOrigin, async (c) => c.json({ nonce: await mintNonce(c.env.NOTES) }));

auth.post("/auth/apple", requireSameOrigin, async (c) => {
  const body = await c.req.json<{ idToken?: string; nonce?: string; name?: string; next?: string }>().catch(() => null);
  if (!body?.idToken || !body.nonce) return c.json({ error: "Malformed request." }, 400);
  if (!c.env.APPLE_WEB_CLIENT_ID) return c.json({ error: "Sign in with Apple isn't set up on this site yet." }, 503);
  let claims;
  try { claims = await verifyAppleIdentityToken(body.idToken, appleAudiences(c.env)); }
  catch { return c.json({ error: "Apple didn't vouch for that sign-in. Try again." }, 401); }
  if (!(await consumeNonce(c.env.NOTES, body.nonce, claims.nonce))) return c.json({ error: "That sign-in took too long. Try again." }, 400);
  const head = await findOrCreateAppleHead(c.env.NOTES, claims.sub, body.name ?? null);
  if (head.disabled_at) return c.json({ error: "That account's been frozen." }, 403);
  await createSession(c, head.id);
  return c.json({ ok: true, next: head.created ? "/me?welcome=1" : safeNext(body.next) });
});

// --- Sign in ----------------------------------------------------------------

auth.get("/signin", (c) => {
  if (c.get("head")) return c.redirect(safeNext(c.req.query("next")), 303);
  return c.html(render(<Frame title="Sign in" crumb={["Sign in"]} head={null} page="signin" bus appleClientId={c.env.APPLE_WEB_CLIENT_ID ?? null}><SignIn next={safeNext(c.req.query("next"))} /></Frame>));
});

auth.post("/signin", async (c) => {
  return c.html(render(<Frame title="Sign in" crumb={["Sign in"]} head={null} page="signin" bus appleClientId={c.env.APPLE_WEB_CLIENT_ID ?? null}><SignIn error={NO_JS} /></Frame>), 400);
});

auth.post("/signin/options", requireSameOrigin, async (c) => {
  const body = await c.req.json<{ handle?: string }>().catch(() => ({} as { handle?: string }));
  let allow: PasskeyRow[] = [];
  let userId: string | null = null;
  if (body.handle && body.handle.trim()) {
    const parsed = parseHandle(body.handle, { allowReserved: true });
    if ("error" in parsed) return c.json({ error: parsed.error }, 400);
    const user = await one<{ id: string; disabled_at: string | null }>(c.env.NOTES, "SELECT id, disabled_at FROM users WHERE handle=?", parsed.handle);
    if (!user) return c.json({ error: "No head by that handle." }, 404);
    userId = user.id;
    allow = await passkeysFor(c.env.NOTES, user.id);
    if (allow.length === 0) return c.json({ error: "That handle has no passkey left. Use the recovery code." }, 400);
  }
  const options = await authenticationOptions(c, allow);
  const ceremonyId = await beginCeremony(c.env.NOTES, "signin", userId, options.challenge, null);
  return c.json({ ceremonyId, options });
});

auth.post("/signin/verify", requireSameOrigin, async (c) => {
  const body = await c.req.json<{ ceremonyId?: string; credential?: any; next?: string }>().catch(() => null);
  if (!body?.ceremonyId || !body.credential?.id) return c.json({ error: "Malformed request." }, 400);
  const ceremony = await consumeCeremony(c.env.NOTES, body.ceremonyId, "signin");
  if (!ceremony) return c.json({ error: "That took too long. Try again." }, 400);
  const passkey = await one<PasskeyRow & { disabled_at: string | null }>(c.env.NOTES,
    `SELECT p.id, p.user_id, p.public_key, p.counter, p.transports, p.device_type, p.backed_up, p.label, p.created_at, p.last_used_at, u.disabled_at
     FROM passkeys p JOIN users u ON u.id = p.user_id WHERE p.id=?`, String(body.credential.id));
  if (!passkey || (ceremony.user_id && ceremony.user_id !== passkey.user_id)) return c.json({ error: "That passkey isn't on the bus. Try another, or use your recovery code." }, 400);
  if (passkey.disabled_at) return c.json({ error: "That handle's been frozen." }, 403);
  let info;
  try { info = await verifyAuthentication(c, body.credential, ceremony.challenge, passkey); } catch { info = null; }
  if (!info) return c.json({ error: "That passkey didn't check out. Try again, or use your recovery code." }, 400);
  await stmt(c.env.NOTES, "UPDATE passkeys SET counter=?, last_used_at=? WHERE id=?", info.newCounter, nowIso(), passkey.id).run();
  await createSession(c, passkey.user_id);
  return c.json({ ok: true, next: safeNext(body.next) });
});

// --- Sign out ---------------------------------------------------------------

auth.post("/signout", async (c) => {
  await revokeCurrent(c);
  return c.redirect("/", 303);
});

auth.post("/signout/everywhere", requireHead(), async (c) => {
  await revokeAll(c, c.get("head")!.id, false);
  return c.redirect("/", 303);
});

// --- Recovery ---------------------------------------------------------------

auth.get("/recover", (c) => c.html(render(<Frame title="Back on the bus" crumb={["Recover"]} head={null} page="signin" bus appleClientId={c.env.APPLE_WEB_CLIENT_ID ?? null}><Recover /></Frame>)));

auth.post("/recover", async (c) => {
  const form = await c.req.parseBody();
  const rawHandle = String(form.handle ?? "");
  const code = String(form.code ?? "");
  const page = (error: string, status: 400 | 429 = 400) =>
    c.html(render(<Frame title="Back on the bus" crumb={["Recover"]} head={null} page="signin" bus appleClientId={c.env.APPLE_WEB_CLIENT_ID ?? null}><Recover handle={rawHandle} error={error} /></Frame>), status);
  const parsed = parseHandle(rawHandle, { allowReserved: true });
  if ("error" in parsed) return page("That handle and code don't match.");
  const fails = await one<{ n: number }>(c.env.NOTES,
    "SELECT COUNT(*) AS n FROM ceremonies WHERE kind='recovery_fail' AND payload_json=? AND expires_at > ?", parsed.handle, nowIso());
  if ((fails?.n ?? 0) >= 10) return page("Too many tries on that handle. Come back in an hour.", 429);
  const user = await one<{ id: string; recovery_hash: string; disabled_at: string | null }>(c.env.NOTES, "SELECT id, recovery_hash, disabled_at FROM users WHERE handle=?", parsed.handle);
  const ok = user && !user.disabled_at && (await verifyCode(code, user.recovery_hash));
  if (!ok) {
    await stmt(c.env.NOTES, "INSERT INTO ceremonies (id, kind, user_id, challenge, payload_json, created_at, expires_at) VALUES (?,?,?,?,?,?,?)",
      uuid(), "recovery_fail", null, "-", parsed.handle, nowIso(), isoPlus(3600)).run();
    return page("That handle and code don't match.");
  }
  const options = await registrationOptions(c, { userId: user.id, handle: parsed.handle, exclude: [] });
  const ceremonyId = await beginCeremony(c.env.NOTES, "recovery", user.id, options.challenge, { handle: parsed.handle });
  return c.html(render(<Frame title="Back on the bus" crumb={["Recover"]} head={null} page="signin" bus appleClientId={c.env.APPLE_WEB_CLIENT_ID ?? null}>
    <RecoverPasskey handle={parsed.handle} ceremonyId={ceremonyId} optionsJson={JSON.stringify(options)} />
  </Frame>));
});

auth.post("/recover/verify", requireSameOrigin, async (c) => {
  const body = await c.req.json<{ ceremonyId?: string; credential?: any }>().catch(() => null);
  if (!body?.ceremonyId || !body.credential) return c.json({ error: "Malformed request." }, 400);
  const ceremony = await consumeCeremony(c.env.NOTES, body.ceremonyId, "recovery");
  if (!ceremony?.user_id) return c.json({ error: "That took too long. Start again from the code." }, 400);
  let reg;
  try { reg = await verifyRegistration(c, body.credential, ceremony.challenge); } catch { reg = null; }
  if (!reg) return c.json({ error: "That passkey didn't check out. Reload and try again." }, 400);
  const code = generateRecoveryCode();
  const now = nowIso();
  const label = labelFor(c.req.header("user-agent") ?? "", body.credential.authenticatorAttachment);
  await c.env.NOTES.batch([
    stmt(c.env.NOTES, "INSERT INTO passkeys (id, user_id, public_key, counter, transports, device_type, backed_up, label, created_at) VALUES (?,?,?,?,?,?,?,?,?)",
      reg.id, ceremony.user_id, blob(reg.publicKey), reg.counter, JSON.stringify(reg.transports), reg.deviceType, reg.backedUp ? 1 : 0, label, now),
    stmt(c.env.NOTES, "UPDATE users SET recovery_hash=?, recovery_rotated_at=?, updated_at=? WHERE id=?", await hashCode(code), now, now, ceremony.user_id),
    stmt(c.env.NOTES, "DELETE FROM sessions WHERE user_id=?", ceremony.user_id),
  ]);
  await createSession(c, ceremony.user_id);
  return c.json({ ok: true, recoveryCode: code, next: "/me/passkeys" });
});

// --- Passkeys ---------------------------------------------------------------

auth.get("/me/passkeys", requireHead(), async (c) => {
  const head = c.get("head")!;
  const list = await passkeysFor(c.env.NOTES, head.id);
  const ok = c.req.query("ok") === "added" ? "Passkey added." : c.req.query("ok") === "removed" ? "Passkey removed." : null;
  return c.html(render(<Frame title="Passkeys" crumb={[head.handle, "passkeys"]} head={head} page="me" bus><Passkeys head={head} passkeys={list} ok={ok} error={c.req.query("error") ?? null} /></Frame>));
});

auth.post("/me/passkeys/options", requireSameOrigin, requireHead(), async (c) => {
  const head = c.get("head")!;
  const existing = await passkeysFor(c.env.NOTES, head.id);
  const options = await registrationOptions(c, { userId: head.id, handle: head.handle, exclude: existing });
  const ceremonyId = await beginCeremony(c.env.NOTES, "add_passkey", head.id, options.challenge, null);
  return c.json({ ceremonyId, options });
});

auth.post("/me/passkeys/verify", requireSameOrigin, requireHead(), async (c) => {
  const head = c.get("head")!;
  const body = await c.req.json<{ ceremonyId?: string; credential?: any; label?: string }>().catch(() => null);
  if (!body?.ceremonyId || !body.credential) return c.json({ error: "Malformed request." }, 400);
  const ceremony = await consumeCeremony(c.env.NOTES, body.ceremonyId, "add_passkey");
  if (!ceremony || ceremony.user_id !== head.id) return c.json({ error: "That took too long. Try again." }, 400);
  let reg;
  try { reg = await verifyRegistration(c, body.credential, ceremony.challenge); } catch { reg = null; }
  if (!reg) return c.json({ error: "That passkey didn't check out." }, 400);
  const label = (body.label ?? "").trim().slice(0, 40) || labelFor(c.req.header("user-agent") ?? "", body.credential.authenticatorAttachment);
  await stmt(c.env.NOTES, "INSERT INTO passkeys (id, user_id, public_key, counter, transports, device_type, backed_up, label, created_at) VALUES (?,?,?,?,?,?,?,?,?)",
    reg.id, head.id, blob(reg.publicKey), reg.counter, JSON.stringify(reg.transports), reg.deviceType, reg.backedUp ? 1 : 0, label, nowIso()).run();
  return c.json({ ok: true });
});

auth.post("/me/passkeys/:id/delete", requireHead(), async (c) => {
  const head = c.get("head")!;
  const id = c.req.param("id");
  const form = await c.req.parseBody();
  const list = await passkeysFor(c.env.NOTES, head.id);
  if (!list.some((p) => p.id === id)) return c.notFound();
  if (list.length === 1 && form.have_recovery_code !== "1") {
    return c.redirect("/me/passkeys?error=" + encodeURIComponent("That's your last passkey. Tick the box if you have the recovery code, or add another passkey first."), 303);
  }
  await stmt(c.env.NOTES, "DELETE FROM passkeys WHERE id=? AND user_id=?", id, head.id).run();
  return c.redirect("/me/passkeys?ok=removed", 303);
});

auth.post("/me/passkeys/:id", requireHead(), async (c) => {
  const head = c.get("head")!;
  const form = await c.req.parseBody();
  const label = String(form.label ?? "").trim().slice(0, 40);
  await stmt(c.env.NOTES, "UPDATE passkeys SET label=? WHERE id=? AND user_id=?", label || null, c.req.param("id"), head.id).run();
  return c.redirect("/me/passkeys", 303);
});

auth.post("/me/recovery/rotate", requireHead(), async (c) => {
  const head = c.get("head")!;
  const code = generateRecoveryCode();
  const now = nowIso();
  await stmt(c.env.NOTES, "UPDATE users SET recovery_hash=?, recovery_rotated_at=?, updated_at=? WHERE id=?", await hashCode(code), now, now, head.id).run();
  return c.html(render(<Frame title="Recovery code" crumb={[head.handle, "recovery"]} head={head} page="me"><NewCode code={code} /></Frame>));
});

export { q };
