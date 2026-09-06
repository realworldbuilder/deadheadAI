/**
 * The knowledge base the iOS app ships — imported from its home so there is
 * one copy. Eras, the famous runs, song histories, the nights heads name,
 * and the quotes.
 */
import erasJson from "../../ShakedownAI/Resources/knowledge_base/eras.json";
import runsJson from "../../ShakedownAI/Resources/knowledge_base/runs.json";
import songsJson from "../../ShakedownAI/Resources/knowledge_base/songs.json";
import notableJson from "../../ShakedownAI/Resources/knowledge_base/notable_shows.json";
import quotesJson from "../../ShakedownAI/Resources/knowledge_base/quotes.json";

export interface Era {
  id: string; name: string; years: string; startYear: number; endYear: number;
  lineup: string; style: string; summary: string; beginnerShows: string[]; mustHear: string[]; context: string;
}
export interface FamousRun {
  id: string; date: string; title: string; songKeys: string[]; blurb: string; eraID: string; tags: string[];
}
export interface SongInfo {
  key: string; title: string; writtenBy: string; debut: string; lastPlayed: string; timesPlayed: number;
  evolution: string; famousVersions: { date: string; note: string; label: string }[]; seguePartners: string[]; tags: string[];
}
export interface NotableShow {
  date: string; venue: string; location: string; eraID: string; tags: string[]; blurb: string;
  standoutSongs: string[]; preferredIdentifier: string;
}
export interface BandQuote { text: string; attribution: string }

export const eras = erasJson as Era[];
export const runs = runsJson as FamousRun[];
export const songs = songsJson as SongInfo[];
export const notableShows = notableJson as NotableShow[];
export const quotes = quotesJson as BandQuote[];

export function eraForYear(year: number): Era | null {
  return eras.find((e) => year >= e.startYear && year <= e.endYear) ?? null;
}

export function eraById(id: string | null | undefined): Era | null {
  return id ? eras.find((e) => e.id === id) ?? null : null;
}

export function runsOn(date: string): FamousRun[] {
  return runs.filter((r) => r.date === date);
}

export function notableShow(date: string): NotableShow | null {
  return notableShows.find((n) => n.date === date) ?? null;
}

export function songInfo(key: string): SongInfo | null {
  return songs.find((s) => s.key === key) ?? null;
}

export function quoteFor(dayOfYear: number): BandQuote {
  return quotes[dayOfYear % quotes.length]!;
}

export function notableFor(dayOfYear: number): NotableShow {
  return notableShows[dayOfYear % notableShows.length]!;
}
