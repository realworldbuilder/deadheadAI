// A full sign-up trip against a live host with the test authenticator, then leave the bus. Node 23+.
import { SoftAuthenticator } from "../test/softauth.ts";
const ORIGIN = process.argv[2] ?? "https://nethead.nethead-web.workers.dev";
const name = "PROBE" + Math.floor(Math.random() * 9000 + 1000);
const json = (path, body, cookie) => fetch(ORIGIN + path, { method: "POST", body: JSON.stringify(body),
  headers: { "content-type": "application/json", origin: ORIGIN, "sec-fetch-site": "same-origin", ...(cookie ? { cookie } : {}) } });
const auth = new SoftAuthenticator();
const o = await json("/bus/options", { node: "TEST", name, first_show: "11/18/1987" });
console.log("options", o.status);
const { ceremonyId, options } = await o.json();
const credential = await auth.create(options, ORIGIN);
const v = await json("/bus/verify", { ceremonyId, credential });
const text = await v.text();
console.log("verify", v.status, v.headers.get("content-type"), text.slice(0, 300));
if (v.status === 200) {
  const cookie = (v.headers.get("set-cookie") ?? "").split(";")[0];
  const me = await fetch(ORIGIN + "/me", { headers: { cookie }, redirect: "manual" });
  console.log("/me", me.status);
  const leave = await fetch(ORIGIN + "/me/delete", { method: "POST", redirect: "manual", headers: { cookie, origin: ORIGIN, "content-type": "application/x-www-form-urlencoded" }, body: "confirm_handle=TEST::" + name });
  console.log("leave", leave.status);
}
