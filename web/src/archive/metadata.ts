/**
 * archive.org's /metadata/{identifier}, through the Cache API: six hours
 * fresh, a week stale, and the stale copy served when archive.org doesn't
 * answer. Only `files`, `reviews` and a few `metadata` fields are kept.
 */
import { buildTracks, type IAFile, type Track } from "./files";
import type { Review } from "../views/tape";

const FRESH_SECONDS = 6 * 3600;
const KEEP_SECONDS = 7 * 86400;
const USER_AGENT = "Nethead-notesfile/1.0 (+https://github.com/realworldbuilder/deadheadAI)";

export interface TapeInfo { tracks: Track[] | null; reviews: Review[]; venue: string | null; date: string | null }

interface IAResponse {
  metadata?: { venue?: string | string[]; date?: string | string[]; title?: string };
  files?: IAFile[];
  reviews?: { reviewtitle?: string; reviewbody?: string; stars?: string | number; reviewer?: string; reviewdate?: string }[];
}

export async function fetchTape(identifier: string, ctx: { waitUntil(p: Promise<unknown>): void }, opts: { needTracks: boolean }): Promise<TapeInfo | null> {
  const url = `https://archive.org/metadata/${encodeURIComponent(identifier)}`;
  const cache = (caches as unknown as { default: Cache }).default;
  const key = new Request(url);
  const hit = await cache.match(key);
  const fetchedAt = hit ? Number(hit.headers.get("x-fetched-at") ?? 0) : 0;
  const fresh = hit && Date.now() - fetchedAt < FRESH_SECONDS * 1000;
  if (hit && fresh) return parse(await hit.json<IAResponse>(), opts);
  try {
    const res = await fetch(url, { headers: { "user-agent": USER_AGENT, accept: "application/json" }, signal: AbortSignal.timeout(8000) });
    if (!res.ok) throw new Error(`archive ${res.status}`);
    const body = await res.text();
    const stored = new Response(body, {
      headers: { "content-type": "application/json", "cache-control": `public, max-age=${KEEP_SECONDS}`, "x-fetched-at": String(Date.now()) },
    });
    ctx.waitUntil(cache.put(key, stored));
    return parse(JSON.parse(body) as IAResponse, opts);
  } catch {
    if (hit) return parse(await hit.json<IAResponse>(), opts);
    return null;
  }
}

function parse(raw: IAResponse, opts: { needTracks: boolean }): TapeInfo {
  const md = raw.metadata ?? {};
  const first = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] ?? null : v ?? null);
  return {
    tracks: opts.needTracks ? buildTracks(raw.files ?? []) : null,
    reviews: (raw.reviews ?? []).map((r) => ({
      title: r.reviewtitle ?? null, body: r.reviewbody ?? null,
      stars: r.stars != null && r.stars !== "" ? Number(r.stars) : null,
      reviewer: r.reviewer ?? null, date: r.reviewdate ?? null,
    })),
    venue: first(md.venue), date: first(md.date),
  };
}
