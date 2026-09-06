/** JSON endpoints only answer the site's own pages. */
import type { MiddlewareHandler } from "hono";
import type { App } from "../env";

export const requireSameOrigin: MiddlewareHandler<App> = async (c, next) => {
  const site = c.req.header("sec-fetch-site");
  const origin = c.req.header("origin");
  const self = new URL(c.req.url).origin;
  const ok = site ? site === "same-origin" || site === "none" : origin === self || origin == null;
  if (!ok) return c.json({ error: "Not from here." }, 403);
  const type = c.req.header("content-type") ?? "";
  if (c.req.method !== "GET" && !type.startsWith("application/json")) return c.json({ error: "JSON only." }, 415);
  await next();
};
