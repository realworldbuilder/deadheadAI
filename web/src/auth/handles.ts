/** Handles in DECnotes form: NODE::NAME, letters, digits and underscore, 2–12 each. */

export const HANDLE_RE = /^([A-Z0-9_]{2,12})::([A-Z0-9_]{2,12})$/;

/** The house node is for admins; the rest would confuse a reader or a URL. */
export const RESERVED_NODES = new Set(["ADMIN", "SYSTEM", "ROOT", "NETHEAD", "RDVAX", "NULL", "NONE", "DECK", "NOTES"]);
export const RESERVED_NAMES = new Set(["ADMIN", "MODERATOR", "SYSTEM", "ROOT", "NETHEAD", "GRATEFUL", "DEADHEAD", "NULL", "NONE", "DELETED", "ANONYMOUS"]);

/** Nodes to pick from on the bus. Real DECnet nodes from the conference, plus a few of ours. */
export const NODE_PICKS = ["NACAD2", "CSLALL", "CSCMA", "PHISH", "TERRAPIN", "BARTON", "HAMPTON", "WINTERLAND", "FILLMORE", "SHAKEDOWN", "MSG", "FROST"];

export interface ParsedHandle { handle: string; node: string; name: string }

export const HANDLE_HELP = "A handle looks like NODE::NAME — letters, digits, underscore, 2 to 12 each. PHISH::HUSSEY, CSLALL::HENDERSON.";

export function parseHandle(raw: string, opts: { allowReserved?: boolean } = {}): ParsedHandle | { error: string } {
  const text = raw.trim().toUpperCase().replace(/\s+/g, "");
  const m = HANDLE_RE.exec(text);
  if (!m) return { error: HANDLE_HELP };
  const node = m[1]!, name = m[2]!;
  if (/^_+$/.test(node) || /^_+$/.test(name)) return { error: "Underscores alone aren't a handle." };
  if (!opts.allowReserved && (RESERVED_NODES.has(node) || RESERVED_NAMES.has(name))) {
    return { error: `${node}::${name} is spoken for. Try another node, or another name.` };
  }
  return { handle: `${node}::${name}`, node, name };
}

export function handleFromParts(node: string, name: string, opts: { allowReserved?: boolean } = {}) {
  return parseHandle(`${node}::${name}`, opts);
}
