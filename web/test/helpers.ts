/** Shared test helpers: the sign-up trip and request shorthands. */
import { SELF } from "cloudflare:test";
import { expect } from "vitest";
import type { SoftAuthenticator } from "./softauth";

export const ORIGIN = "https://nethead.test";

export const json = (path: string, body: unknown, cookie?: string) => SELF.fetch(ORIGIN + path, {
  method: "POST", body: JSON.stringify(body),
  headers: { "content-type": "application/json", "sec-fetch-site": "same-origin", origin: ORIGIN, ...(cookie ? { cookie } : {}) },
});

export const form = (path: string, fields: Record<string, string>, cookie?: string) => SELF.fetch(ORIGIN + path, {
  method: "POST", body: new URLSearchParams(fields).toString(), redirect: "manual",
  headers: { "content-type": "application/x-www-form-urlencoded", origin: ORIGIN, ...(cookie ? { cookie } : {}) },
});

export const get = (path: string, cookie?: string) => SELF.fetch(ORIGIN + path, { redirect: "manual", headers: cookie ? { cookie } : {} });

export const cookieOf = (res: Response) => (res.headers.get("set-cookie") ?? "").split(";")[0]!;

/** The whole trip: options → passkey → verify. Returns the session cookie and the code. */
export async function signUp(auth: SoftAuthenticator, node: string, name: string, firstShow = "5/8/77") {
  const o = await json("/bus/options", { node, name, first_show: firstShow });
  expect(o.status, await o.clone().text()).toBe(200);
  const { ceremonyId, options } = await o.json<{ ceremonyId: string; options: any }>();
  const credential = await auth.create(options, ORIGIN);
  const v = await json("/bus/verify", { ceremonyId, credential });
  expect(v.status, await v.clone().text()).toBe(200);
  const body = await v.json<{ handle: string; recoveryCode: string }>();
  return { cookie: cookieOf(v), handle: body.handle, code: body.recoveryCode, credentialId: credential.id };
}

export async function signIn(auth: SoftAuthenticator, handle: string | undefined, credentialId?: string) {
  const o = await json("/signin/options", handle ? { handle } : {});
  expect(o.status, await o.clone().text()).toBe(200);
  const { ceremonyId, options } = await o.json<{ ceremonyId: string; options: any }>();
  const credential = await auth.get(options, ORIGIN, credentialId);
  const v = await json("/signin/verify", { ceremonyId, credential, next: "/me" });
  return { res: v, cookie: cookieOf(v) };
}
