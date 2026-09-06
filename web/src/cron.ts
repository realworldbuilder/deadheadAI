/** Every six hours: expired sessions and ceremonies, spins older than a day. */
import type { Bindings } from "./env";
import { isoMinus, nowIso } from "./db/ids";

export async function purge(env: Bindings): Promise<void> {
  const now = nowIso();
  await env.NOTES.batch([
    env.NOTES.prepare("DELETE FROM sessions WHERE expires_at < ?").bind(now),
    env.NOTES.prepare("DELETE FROM ceremonies WHERE expires_at < ?").bind(now),
    env.NOTES.prepare("DELETE FROM spins WHERE updated_at < ?").bind(isoMinus(86400)),
  ]);
}
