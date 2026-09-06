/**
 * Setlist ↔ tape alignment, the way the phone does it (SetlistMatcher /
 * TapeSetlist in the app): monotonic greedy matching by exact key or
 * whole-word containment, scanning forward only.
 */
import type { SetlistEntry } from "./queries";
import type { Track } from "../archive/files";

/** Track.normalizeSongKey: lowercase, arrows out, only [a-z' ] kept, spaces collapsed. */
export function normalizeSongKey(title: string): string {
  let t = title.toLowerCase();
  for (const arrow of ["-->", "->", ">"]) t = t.split(arrow).join("");
  t = t.replace(/[^a-z' ]/g, " ").replace(/\s+/g, " ");
  return t.trim();
}

export function keyMatches(trackKey: string, key: string): boolean {
  if (trackKey === key) return true;
  return (" " + trackKey + " ").includes(" " + key + " ");
}

/** For each setlist entry (by position order), the index of the track that carries it, or null. */
export function align(entries: SetlistEntry[], tracks: Track[], aliases: Record<string, string> = {}): (number | null)[] {
  const trackKeys = tracks.map((t) => {
    const k = normalizeSongKey(t.title);
    return aliases[k] ?? k;
  });
  let cursor = 0;
  const out: (number | null)[] = [];
  for (const entry of [...entries].sort((a, b) => a.position - b.position)) {
    const key = entry.song_key;
    if (!key) { out.push(null); continue; }
    let found: number | null = null;
    const start = Math.max(0, cursor - 1);
    for (let i = start; i < trackKeys.length; i++) {
      if (keyMatches(trackKeys[i]!, key)) { found = i; break; }
    }
    out.push(found);
    if (found != null) cursor = found + 1;
  }
  return out;
}

export type Row =
  | { kind: "heading"; label: string }
  | { kind: "track"; index: number; segues: boolean }
  | { kind: "missing"; entry: SetlistEntry };

/** The tape's tracks laid out as one list shaped by the setlist (TapeSetlist.rows). */
export function rows(entries: SetlistEntry[], tracks: Track[], aliases: Record<string, string> = {}): Row[] {
  if (entries.length === 0) return tracks.map((_, i) => ({ kind: "track", index: i, segues: false }));
  const sorted = [...entries].sort((a, b) => a.position - b.position);
  const matched = align(sorted, tracks, aliases);
  const out: Row[] = [];
  const rowForTrack = new Map<number, number>();
  let cursor = 0;
  const emit = (index: number, segues: boolean) => {
    const at = rowForTrack.get(index);
    if (at != null) {
      const r = out[at]!;
      if (segues && r.kind === "track" && !r.segues) out[at] = { kind: "track", index: r.index, segues: true };
      return;
    }
    rowForTrack.set(index, out.length);
    out.push({ kind: "track", index, segues });
  };
  let label: string | null = null;
  sorted.forEach((entry, n) => {
    if (entry.set_label !== label) {
      label = entry.set_label;
      out.push({ kind: "heading", label });
    }
    const idx = matched[n];
    if (idx == null) { out.push({ kind: "missing", entry }); return; }
    while (cursor < idx) { emit(cursor, false); cursor++; }
    emit(idx, entry.segues_into_next === 1);
    cursor = Math.max(cursor, idx + 1);
  });
  while (cursor < tracks.length) { emit(cursor, false); cursor++; }
  return out;
}
