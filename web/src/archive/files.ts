/**
 * Which files on a tape are the tracks and what they're called — the same
 * rules as the app's ArchiveAPIClient and the pipeline's tracks.py, so the
 * deck sees the titles the phone sees.
 */

export interface Track { title: string; seconds: number | null; fileName: string }

export interface IAFile { name: string; format?: string; title?: string; track?: string | number; length?: string | number }

export const MP3_FORMAT_PREFERENCE = ["vbr mp3", "128kbps mp3", "64kbps mp3"];

const PREFIX_RE = /^gd\d{2,4}-\d{2}-\d{2}[a-z0-9.]*(d\d+)?t\d+[. ]?/;

export function playableFiles(files: IAFile[]): IAFile[] {
  for (const fmt of MP3_FORMAT_PREFERENCE) {
    const matches = files.filter((f) => (f.format ?? "").toLowerCase() === fmt);
    if (matches.length) return matches;
  }
  return files.filter((f) => (f.format ?? "").toLowerCase().includes("mp3") && f.name.toLowerCase().endsWith(".mp3"));
}

export function titleFromFileName(name: string): string {
  let base = name.replace(/\.[^./]*$/, "");
  base = base.replace(PREFIX_RE, "");
  base = base.split("_").join(" ");
  return base || name;
}

/** "01 Shakedown Street" → "Shakedown Street"; years and bare numbers stay. */
export function stripLeadingTrackNumber(title: string): string {
  const stripped = title.replace(/^\s*\d{1,3}\s*[.\-–:)]?\s+/, "").trim();
  return stripped || title;
}

/** "mm:ss", "hh:mm:ss" or "432.18" → seconds. */
export function durationSeconds(length: string | number | null | undefined): number | null {
  if (length == null) return null;
  const text = String(length).trim();
  if (!text) return null;
  if (/^\d+(\.\d+)?$/.test(text)) return Number(text);
  const parts = text.split(":").map(Number);
  if (parts.some((n) => Number.isNaN(n))) return null;
  let total = 0;
  parts.reverse().forEach((v, i) => { total += v * 60 ** i; });
  return total;
}

export function trackNumber(track: string | number | null | undefined): number | null {
  if (track == null) return null;
  const m = /^\d+/.exec(String(track));
  return m ? Number(m[0]) : null;
}

/** The tape's tracks in play order from an archive.org metadata `files` list. */
export function buildTracks(files: IAFile[]): Track[] {
  const rows = playableFiles(files).map((f) => ({
    fileName: f.name,
    title: f.title || titleFromFileName(f.name),
    track: trackNumber(f.track),
    seconds: durationSeconds(f.length),
  }));
  rows.sort((a, b) => {
    if (a.track != null && b.track != null && a.track !== b.track) return a.track - b.track;
    if (a.track != null && b.track == null) return -1;
    if (a.track == null && b.track != null) return 1;
    return a.fileName < b.fileName ? -1 : a.fileName > b.fileName ? 1 : 0;
  });
  return rows.map(({ fileName, title, seconds }) => ({ fileName, title, seconds }));
}

/** The catalog's compact `[title, seconds, file]` triples → tracks. */
export function parseTracksJson(json: string | null): Track[] {
  if (!json) return [];
  try {
    const raw = JSON.parse(json) as [string, number | null, string][];
    return raw.map(([title, seconds, fileName]) => ({ title, seconds, fileName }));
  } catch {
    return [];
  }
}

export function streamUrl(identifier: string, fileName: string): string {
  const path = fileName.split("/").map(encodeURIComponent).join("/");
  return `https://archive.org/download/${encodeURIComponent(identifier)}/${path}`;
}

export function detailsUrl(identifier: string): string {
  return `https://archive.org/details/${encodeURIComponent(identifier)}`;
}

export function totalSeconds(tracks: Track[]): number {
  return tracks.reduce((sum, t) => sum + (t.seconds ?? 0), 0);
}
