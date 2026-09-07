import { Hono } from "hono";
import type { App } from "../env";
import { q } from "../db/notes";
import { Frame, render } from "../views/frame";
import { Lot, type SpinRow } from "../views/lot";

export const lot = new Hono<App>();

lot.get("/lot", async (c) => {
  const cutoff = new Date(Date.now() - 20 * 60000).toISOString();
  const [now, earlier] = await Promise.all([
    q<SpinRow>(c.env.NOTES, "SELECT handle, show_id, identifier, track_title, updated_at FROM spins WHERE updated_at > ? ORDER BY updated_at DESC LIMIT 100", cutoff),
    q<SpinRow>(c.env.NOTES, "SELECT handle, show_id, identifier, track_title, updated_at FROM spins WHERE updated_at <= ? ORDER BY updated_at DESC LIMIT 50", cutoff),
  ]);
  return c.html(render(<Frame title="The Lot" crumb={["The Lot"]} head={c.get("head")} page="lot"><Lot now={now} earlier={earlier} /></Frame>));
});
