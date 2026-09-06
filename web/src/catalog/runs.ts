/** Anchor a famous run (from runs.json) to a tape's tracks, the way RunResolver does. */
import type { Track } from "../archive/files";
import type { FamousRun } from "../kb";
import { keyMatches, normalizeSongKey } from "./setlist";

const BRIDGES = new Set(["drums", "space", "drums space", "jam"]);

/** Start and end track index of the run on this tape, or null if the tape doesn't carry it whole. */
export function resolveRun(run: FamousRun, tracks: Track[]): { from: number; to: number } | null {
  const keys = tracks.map((t) => normalizeSongKey(t.title));
  const wanted = run.songKeys.filter((k) => !BRIDGES.has(k));
  if (wanted.length === 0) return null;
  for (let start = 0; start < keys.length; start++) {
    if (!keyMatches(keys[start]!, wanted[0]!)) continue;
    let cursor = start;
    let ok = true;
    for (let n = 1; n < wanted.length; n++) {
      let found = -1;
      for (let i = cursor; i < Math.min(keys.length, cursor + 4); i++) {
        if (keyMatches(keys[i]!, wanted[n]!)) { found = i; break; }
        if (!BRIDGES.has(keys[i]!) && i > cursor) break;
      }
      if (found < 0) { ok = false; break; }
      cursor = found;
    }
    if (ok) return { from: start, to: cursor };
  }
  return null;
}

export function resolveRuns(runs: FamousRun[], tracks: Track[]) {
  const out: { run: FamousRun; from: number; to: number }[] = [];
  const seen = new Set<string>();
  for (const run of runs) {
    const r = resolveRun(run, tracks);
    if (r && !seen.has(run.title)) { seen.add(run.title); out.push({ run, ...r }); }
  }
  return out;
}

/** Setlist entries with segue flags filled in from the curated runs (the catalog flags few). */
export function withRunSegues<T extends { song_key: string; segues_into_next: number }>(entries: T[], runs: FamousRun[]): T[] {
  if (!runs.length) return entries;
  const out = entries.map((e) => ({ ...e }));
  for (const run of runs) {
    const wanted = run.songKeys.filter((k) => !BRIDGES.has(k));
    for (let n = 0; n + 1 < wanted.length; n++) {
      const a = wanted[n]!, b = wanted[n + 1]!;
      for (let i = 0; i + 1 < out.length; i++) {
        if (!keyMatches(out[i]!.song_key, a)) continue;
        let j = i + 1;
        while (j < out.length && BRIDGES.has(out[j]!.song_key)) j++;
        if (j < out.length && keyMatches(out[j]!.song_key, b)) {
          for (let k = i; k < j; k++) out[k]!.segues_into_next = 1;
        }
      }
    }
  }
  return out;
}
