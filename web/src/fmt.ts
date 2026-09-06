/** Every date, time and number the notesfile prints goes through here. */

const MONTHS = ["January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"];
const MONTHS_UP = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
const DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})/;

export function parts(iso: string): { y: number; m: number; d: number } | null {
  const m = ISO_DATE.exec(iso);
  if (!m) return null;
  return { y: Number(m[1]), m: Number(m[2]), d: Number(m[3]) };
}

/** "1977-05-08" → "5/8/77", the way heads write it. Anything else passes through. */
export function prettyDate(iso: string): string {
  const p = parts(iso);
  if (!p) return iso;
  return `${p.m}/${p.d}/${String(p.y % 100).padStart(2, "0")}`;
}

/** "1977-05-08" → "Sunday, May 8, 1977" (UTC, so no timezone drift). */
export function longDate(iso: string): string {
  const p = parts(iso);
  if (!p) return iso;
  const date = new Date(Date.UTC(p.y, p.m - 1, p.d));
  return `${DAYS[date.getUTCDay()]}, ${MONTHS[p.m - 1]} ${p.d}, ${p.y}`;
}

/** "9/5" for on-this-day lines. */
export function monthDay(month: number, day: number): string {
  return `${month}/${day}`;
}

/** ISO timestamp → the DECnotes stamp: "08-MAY-1994 09:12" (UTC). */
export function noteStamp(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const dd = String(d.getUTCDate()).padStart(2, "0");
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const mm = String(d.getUTCMinutes()).padStart(2, "0");
  return `${dd}-${MONTHS_UP[d.getUTCMonth()]}-${d.getUTCFullYear()} ${hh}:${mm}`;
}

/** ISO timestamp → "5/8/77"-style date of the stamp. */
export function stampDate(iso: string): string {
  return prettyDate(iso.slice(0, 10));
}

/** 581 → "9:41"; 3612 → "1:00:12"; nothing → "--:--". */
export function mmss(seconds: number | null | undefined): string {
  if (seconds == null || !(seconds > 0)) return "--:--";
  const total = Math.round(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const ms = `${m}:${String(s).padStart(2, "0")}`;
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}` : ms;
}

/** 4283 → "71 min"; 10260 → "2 h 51 min". */
export function mins(seconds: number): string {
  const total = Math.round(seconds / 60);
  if (total < 120) return `${total} min`;
  const h = Math.floor(total / 60);
  const m = total % 60;
  return m === 0 ? `${h} h` : `${h} h ${m} min`;
}

/** 45, 352 → "45.352". */
export function noteNumber(topic: number, reply: number): string {
  return `${topic}.${reply}`;
}

/** "45.352" → {topic: 45, reply: 352} or null. */
export function parseNoteRef(ref: string): { topic: number; reply: number } | null {
  const m = /^(\d+)\.(\d+)$/.exec(ref);
  if (!m) return null;
  return { topic: Number(m[1]), reply: Number(m[2]) };
}

/**
 * A head's date, as typed: "5/8/77", "5-8-77", "1977-05-08", "May 8 1977",
 * or just "1977". Returns ISO (YYYY-MM-DD) for a full date, YYYY for a year,
 * or null.
 */
export function parseHeadDate(raw: string): string | null {
  const text = raw.trim();
  if (!text) return null;
  let m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(text);
  if (m) return iso(Number(m[1]), Number(m[2]), Number(m[3]));
  m = /^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})$/.exec(text);
  if (m) return iso(fullYear(Number(m[3])), Number(m[1]), Number(m[2]));
  m = /^([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{2,4})$/.exec(text);
  if (m) {
    const month = MONTHS.findIndex((name) => name.toLowerCase().startsWith(m![1]!.toLowerCase().slice(0, 3)));
    if (month >= 0) return iso(fullYear(Number(m[3])), month + 1, Number(m[2]));
  }
  m = /^(\d{4})$/.exec(text);
  if (m) return m[1]!;
  m = /^'?(\d{2})$/.exec(text);
  if (m) return String(fullYear(Number(m[1])));
  return null;
}

function fullYear(y: number): number {
  if (y >= 100) return y;
  return y >= 60 ? 1900 + y : 2000 + y;
}

function iso(y: number, m: number, d: number): string | null {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

/** Month-day today in the East, "09-05" and {month, day}. Tonight's show runs on an East Coast clock. */
export function todayMonthDay(now: Date = new Date()): { mm: string; month: number; day: number } {
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", month: "numeric", day: "numeric", year: "numeric" });
  const bits = Object.fromEntries(fmt.formatToParts(now).map((p) => [p.type, p.value]));
  const month = Number(bits.month), day = Number(bits.day);
  return { mm: `${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`, month, day };
}

export function dayOfYear(now: Date = new Date()): number {
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone: "America/New_York", month: "numeric", day: "numeric", year: "numeric" });
  const bits = Object.fromEntries(fmt.formatToParts(now).map((p) => [p.type, p.value]));
  const start = Date.UTC(Number(bits.year), 0, 1);
  const today = Date.UTC(Number(bits.year), Number(bits.month) - 1, Number(bits.day));
  return Math.floor((today - start) / 86400000);
}

/** "1,596" */
export function count(n: number): string {
  return n.toLocaleString("en-US");
}

/** "Barton Hall (Cornell U)" + "Ithaca, NY" pieces. */
export function place(show: { venue?: string | null; city?: string | null; state?: string | null }): string {
  const bits: string[] = [];
  if (show.city) bits.push(show.city);
  if (show.state) bits.push(show.state);
  return bits.join(", ");
}

/** "5/8/77 · Barton Hall (Cornell U) · Ithaca, NY" */
export function showTitle(show: { date: string; venue?: string | null; city?: string | null; state?: string | null }): string {
  const bits = [prettyDate(show.date)];
  if (show.venue) bits.push(show.venue);
  const where = place(show);
  if (where) bits.push(where);
  return bits.join(" · ");
}

/** "SBD" / "AUD" / "MTX" / "FM" / "?" */
export function sourceBadge(type: string | null | undefined): string {
  switch ((type ?? "").toUpperCase()) {
    case "SBD": return "SBD";
    case "AUD": return "AUD";
    case "MATRIX": return "MTX";
    case "FM": return "FM";
    default: return "?";
  }
}

export function rating(n: number | null | undefined): string {
  return n == null ? "—" : n.toFixed(1);
}

/** Setlist rows → the typed-in .txt. Encore → "E:", Encore 2 → "E2:"; a segue is a trailing " >". */
export function setlistLines(entries: { set_label: string; song_title: string; segues_into_next: number }[]): string[] {
  const lines: string[] = [];
  let label: string | null = null;
  for (const e of entries) {
    if (e.set_label !== label) {
      if (label !== null) lines.push("");
      label = e.set_label;
      lines.push(setHeading(label) + ":");
    }
    lines.push(e.song_title + (e.segues_into_next ? " >" : ""));
  }
  return lines;
}

export function setHeading(label: string): string {
  if (label === "Encore") return "E";
  if (label === "Encore 2") return "E2";
  return label;
}

export function showTxt(opts: {
  show: { show_id: string; date: string; venue?: string | null; city?: string | null; state?: string | null; setlist_status: string };
  entries: { set_label: string; song_title: string; segues_into_next: number }[];
  best: { identifier: string; source_type: string; avg_rating: number | null; num_reviews: number; taper?: string | null } | null;
  topicNumber: number | null;
  origin: string;
}): string {
  const { show, entries, best, topicNumber, origin } = opts;
  const out: string[] = ["Grateful Dead"];
  const where = place(show);
  const venueLine = [prettyDate(show.date), show.venue ?? "", where].filter(Boolean).join("  ");
  out.push(wrap72(venueLine));
  out.push(longDate(show.date), "");
  if (entries.length) out.push(...setlistLines(entries));
  else out.push("(no setlist typed in yet)");
  out.push("", "--");
  if (best) {
    const bits = [sourceBadge(best.source_type), rating(best.avg_rating), `${best.num_reviews} reviews`];
    if (best.taper) bits.push(best.taper);
    out.push(`Best tape: ${best.identifier}`);
    out.push(`  (${bits.join(", ")})`);
    out.push(`https://archive.org/details/${best.identifier}`);
  } else {
    out.push("No tape on archive.org for this night.");
  }
  const topic = topicNumber ? `RDVAX::GRATEFUL topic ${topicNumber}  ·  ` : "";
  out.push(`${topic}${origin}/shows/${show.show_id}`);
  return out.join("\n") + "\n";
}

function wrap72(line: string): string {
  if (line.length <= 72) return line;
  const cut = line.lastIndexOf(",", 72);
  if (cut > 0) return line.slice(0, cut + 1) + "\n  " + line.slice(cut + 1).trim();
  return line;
}

/** Pad or trim a column. */
export function pad(text: string, width: number): string {
  if (text.length >= width) return text.slice(0, width);
  return text + " ".repeat(width - text.length);
}

/** "dark star" → "dark-star" (matches stage7's web_song_slugs). */
export function songSlug(key: string): string {
  return key.toLowerCase().replace(/[^a-z0-9 ]/g, "").trim().replace(/\s+/g, "-");
}

/** First sentence of a paragraph, for one-line teasers. */
export function firstSentence(text: string): string {
  const m = /^(.+?[.!?])(\s|$)/.exec(text.trim());
  return m ? m[1]! : text.trim();
}

export function clamp(text: string, max: number): string {
  const t = text.replace(/\s+/g, " ").trim();
  return t.length <= max ? t : t.slice(0, max - 1).trimEnd() + "…";
}

/** A head's public tape list as fixed-column text. */
export function tapeListTxt(opts: {
  handle: string; firstShow: string | null; origin: string;
  shelves: { name: string; items: { show_date: string | null; display_name: string; show_identifier: string }[] }[];
  mixtapes: { name: string; items: { show_date_string: string; track_title: string; duration_seconds: number; show_identifier: string; file_name: string }[] }[];
}): string {
  const out: string[] = [`${opts.handle} tape list`];
  if (opts.firstShow) out.push(opts.firstShow.length === 4 ? `On the bus since '${opts.firstShow.slice(2)}` : `On the bus since ${prettyDate(opts.firstShow)}`);
  out.push(`As of ${prettyDate(new Date().toISOString().slice(0, 10))}`, "");
  if (opts.shelves.length + opts.mixtapes.length === 0) out.push("Nothing public on the shelf.");
  for (const s of opts.shelves) {
    out.push(`${s.name}  (${s.items.length} ${s.items.length === 1 ? "tape" : "tapes"})`);
    for (const i of s.items) out.push(`${pad(i.show_date ? prettyDate(i.show_date) : "", 9)} ${pad(i.display_name.replace(/^\S+\s+/, ""), 34)} ${i.show_identifier}`);
    out.push("");
  }
  for (const m of opts.mixtapes) {
    const secs = m.items.reduce((n, i) => n + (i.duration_seconds || 0), 0);
    out.push(`Mix tape: ${m.name}  (${m.items.length} ${m.items.length === 1 ? "tune" : "tunes"}${secs ? `, ${mins(secs)}` : ""})`);
    for (const i of m.items) out.push(`${pad(i.show_date_string ? prettyDate(i.show_date_string) : "", 9)} ${pad(i.track_title, 30)} ${pad(mmss(i.duration_seconds), 7)} ${i.show_identifier}  ${i.file_name}`);
    out.push("");
  }
  out.push("--", `${opts.origin}/heads/${opts.handle}`);
  return out.join("\n") + "\n";
}
