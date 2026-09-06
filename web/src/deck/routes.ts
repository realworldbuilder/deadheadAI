/** What the deck needs: a tape's tracks as JSON, and where to say what you're spinning. */
import { Hono } from "hono";
import type { App } from "../env";
import * as cat from "../catalog/queries";
import { parseTracksJson, streamUrl, stripLeadingTrackNumber, type Track } from "../archive/files";
import { fetchTape } from "../archive/metadata";
import { one } from "../db/notes";
import { recordSpin, type SpinBody } from "../lot/spins";
import { prettyDate } from "../fmt";
import { requireSameOrigin } from "../auth/csrf";
import { mixtape, mixtapeItems } from "../tapes/store";

export const deck = new Hono<App>();

export interface DeckTrack {
  i: number; title: string; seconds: number | null; url: string; identifier: string;
  date: string; pretty: string; venue: string; page: string;
}

export function deckTracks(identifier: string, show: cat.CatalogShow | null, tracks: Track[]): DeckTrack[] {
  const date = show?.date ?? identifier.slice(2, 12);
  const page = show ? `/shows/${show.show_id}/${identifier}` : `https://archive.org/details/${identifier}`;
  return tracks.map((t, i) => ({
    i, title: stripLeadingTrackNumber(t.title), seconds: t.seconds, url: streamUrl(identifier, t.fileName), identifier,
    date, pretty: prettyDate(date), venue: show?.venue ?? "", page,
  }));
}

deck.get("/deck/tapes/:identifier", async (c) => {
  const identifier = c.req.param("identifier");
  const rec = await cat.recording(c.env.CATALOG, identifier);
  const show = rec ? await cat.show(c.env.CATALOG, rec.show_id) : null;
  let tracks = parseTracksJson(await cat.tracksJson(c.env.CATALOG, identifier));
  if (tracks.length === 0) {
    const live = await fetchTape(identifier, c.executionCtx, { needTracks: true });
    tracks = live?.tracks ?? [];
  }
  if (tracks.length === 0) return c.json({ error: "No streamable tracks on this tape." }, 404);
  c.header("cache-control", "public, max-age=3600");
  return c.json({
    identifier, showId: show?.show_id ?? null, date: show?.date ?? null,
    pretty: show ? prettyDate(show.date) : "", venue: show?.venue ?? "",
    page: show ? `/shows/${show.show_id}/${identifier}` : null,
    tracks: deckTracks(identifier, show, tracks),
  });
});

deck.get("/deck/mixtapes/:id", async (c) => {
  const head = c.get("head");
  const tape = await mixtape(c.env.NOTES, c.req.param("id"));
  if (!tape || (tape.is_private && head?.id !== tape.user_id)) return c.json({ error: "No mix tape by that name." }, 404);
  const owner = await one<{ handle: string }>(c.env.NOTES, "SELECT handle FROM users WHERE id=?", tape.user_id);
  const items = await mixtapeItems(c.env.NOTES, tape.id);
  const tracks: DeckTrack[] = items.map((it, i) => ({
    i, title: it.track_title, seconds: it.duration_seconds || null, url: streamUrl(it.show_identifier, it.file_name), identifier: it.show_identifier,
    date: it.show_date_string, pretty: prettyDate(it.show_date_string), venue: it.show_display_name.replace(/^\S+\s*/, ""),
    page: `/shows/${it.show_date_string}/${it.show_identifier}`,
  }));
  return c.json({ id: tape.id, title: tape.name, page: `/heads/${owner?.handle ?? ""}/mixtapes/${tape.id}`, tracks });
});

deck.post("/deck/spin", requireSameOrigin, async (c) => {
  const head = c.get("head");
  if (!head) return c.body(null, 204);
  const body = await c.req.json<SpinBody>().catch(() => null);
  if (!body) return c.json({ error: "malformed" }, 400);
  await recordSpin(c.env.NOTES, head, body);
  return c.body(null, 204);
});
