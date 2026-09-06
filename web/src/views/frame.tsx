/** The page frame: crumb, one line of nav, main, the shirt line, the deck. */
import type { Child, FC } from "hono/jsx";
import type { Head } from "../env";
import { Deck } from "./deck";

export interface FrameProps {
  title: string;
  crumb: string[];
  head: Head | null;
  page: string;
  bus?: boolean;
  /** The Services ID for Sign in with Apple on the web; the button hides without it. */
  appleClientId?: string | null;
  children?: Child;
}

const NAV: [string, string, string][] = [
  ["shows", "/shows", "Shows"],
  ["years", "/years", "Years"],
  ["otd", "/on-this-day", "On This Day"],
  ["notes", "/notes", "Notes"],
  ["lot", "/lot", "The Lot"],
  ["tapelists", "/tapelists", "Tape Lists"],
  ["search", "/search", "Search"],
];

export const Frame: FC<FrameProps> = ({ title, crumb, head, page, bus, appleClientId, children }) => (
  <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
      <meta name="theme-color" content="#050609" />
      <title>{title} — Nethead</title>
      <link rel="icon" href="/icon.png" type="image/png" />
      <link rel="stylesheet" href="/style.css" />
    </head>
    <body data-head={head?.handle ?? undefined} data-page={page} data-apple-client={appleClientId ?? undefined}>
      <a class="skip" href="#main">Skip to the notes</a>
      <div class="sky" aria-hidden="true"></div>
      <div class="stars" aria-hidden="true"></div>
      <div class="wrap">
        <header class="top">
          <p class="crumb" id="crumb">
            <img src="/icon.png" alt="" width="28" height="28" />
            <a href="/">← Nethead</a>
            {crumb.map((c) => (<span> · {c}</span>))}
          </p>
          <nav class="bar" aria-label="Sections">
            {NAV.map(([id, href, label], i) => (
              <>
                {i > 0 ? " · " : ""}
                <a href={href} aria-current={page === id ? "page" : undefined}>{label}</a>
              </>
            ))}
            <span class="who">
              {head
                ? <a href="/me" aria-current={page === "me" ? "page" : undefined}>{head.handle}</a>
                : <><a href="/bus" data-full>Get on the Bus</a> · <a href="/signin" data-full>Sign in</a></>}
            </span>
          </nav>
        </header>
        <main id="main" tabindex={-1}>{children}</main>
        <footer class="foot">
          <p>Hail, netheads. The word is from 1982 and so is the shirt. <a href="https://realworldbuilder.github.io/deadheadAI/nethead.html">Where the name comes from</a> · Tapes stream from <a href="https://archive.org/details/GratefulDead">archive.org</a>; nothing is re-hosted.</p>
        </footer>
      </div>
      <Deck />
      <script src="/deck.js" defer></script>
      {bus ? <script src="https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js" defer></script> : null}
      {bus ? <script src="/bus.js" defer></script> : null}
    </body>
  </html>
);

export function render(node: unknown): string {
  return "<!doctype html>\n" + String(node);
}
