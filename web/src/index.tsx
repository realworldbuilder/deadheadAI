/** The Nethead notesfile. One Worker: pages, the deck's JSON, the passkey ceremonies. */
import { Hono } from "hono";
import { csrf } from "hono/csrf";
import { secureHeaders } from "hono/secure-headers";
import type { App, Bindings } from "./env";
import { sessionMiddleware } from "./auth/sessions";
import { shows } from "./shows/routes";
import { deck } from "./deck/routes";
import { auth } from "./auth/routes";
import { me } from "./me/routes";
import { notes } from "./notes/routes";
import { heads } from "./heads/routes";
import { tapes } from "./tapes/routes";
import { trees } from "./trees/routes";
import { lot } from "./lot/routes";
import { admin } from "./admin/routes";
import { api } from "./api/routes";
import { Frame, render } from "./views/frame";
import { Broke, NotFound } from "./views/errors";
import { purge } from "./cron";

const app = new Hono<App>();

app.use("*", secureHeaders({ crossOriginEmbedderPolicy: false, crossOriginResourcePolicy: false }));
app.use("*", csrf());
app.use("*", sessionMiddleware);

app.route("/", shows);
app.route("/", deck);
app.route("/", auth);
app.route("/", me);
app.route("/", notes);
app.route("/", heads);
app.route("/", tapes);
app.route("/", trees);
app.route("/", lot);
app.route("/", admin);
app.route("/", api);

app.notFound(async (c) => {
  if (c.env.ASSETS && c.req.method === "GET") {
    const asset = await c.env.ASSETS.fetch(c.req.raw);
    if (asset.status !== 404) return new Response(asset.body, asset);
  }
  return c.html(render(<Frame title="Nothing here" crumb={["GRATEFUL"]} head={c.get("head") ?? null} page="none"><NotFound /></Frame>), 404);
});

const JSON_PATHS = /^\/(bus|signin|recover|me\/passkeys|deck|api)\//;

app.onError((err, c) => {
  console.error(err);
  const detail = String((err as Error)?.message ?? err).slice(0, 300);
  if (/daily row write limit/i.test(detail)) {
    const msg = "The free database is tapped out for the day. Writing comes back at midnight UTC, 8 PM Eastern. Reading and spinning still work.";
    return JSON_PATHS.test(c.req.path) ? c.json({ error: msg, detail }, 503) : c.html(render(<Frame title="Tapped out" crumb={["GRATEFUL"]} head={c.get("head") ?? null} page="none"><h1>Tapped out for today.</h1><p>{msg}</p></Frame>), 503);
  }
  if (JSON_PATHS.test(c.req.path)) return c.json({ error: "Bummer. Something broke on our end. Try again in a minute.", detail }, 500);
  return c.html(render(<Frame title="Bummer" crumb={["GRATEFUL"]} head={c.get("head") ?? null} page="none"><Broke /></Frame>), 500);
});

export default {
  fetch: app.fetch,
  async scheduled(_event: ScheduledEvent, env: Bindings, ctx: ExecutionContext) {
    ctx.waitUntil(purge(env));
  },
};

export { app };
