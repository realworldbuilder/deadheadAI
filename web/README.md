# The Nethead notesfile

The Dead conference, back up: `RDVAX::GRATEFUL` on the web. Every show in the
catalog is a topic, heads write notes under it, tape lists get passed around as
trees, the lot shows who's spinning what, and a tape deck at the bottom of every
page keeps the tape rolling while you read. Handles look like `PHISH::HUSSEY`;
sign-in is a passkey, so there's no email and no password anywhere.

It is one Cloudflare Worker on the free tier: server-rendered HTML (Hono + JSX),
two D1 databases (the catalog the iOS app ships, and the notes), a static folder
with the stylesheet, the deck and the passkey script. No bundler, no SPA.

## Running it

```bash
cd web
npm install                         # .npmrc sets legacy-peer-deps for vitest 4
npm run migrate:local               # the notes schema into wrangler's local D1
(cd ../tools/catalog-pipeline && make d1-local)   # the catalog into local D1 (~15 s)
npm run dev                         # http://localhost:8787
npm test                            # vitest, inside workerd, against real local D1
npm run typecheck && npm run size   # tsc; style.css ≤ 12 KB, deck.js ≤ 14 KB
```

Or from the repo root with the Claude Code browser pane: the `nethead-web`
entry in `.claude/launch.json`.

## Putting it up

Once, by hand:

1. A free Cloudflare account. `cd web && npx wrangler login`.
2. `npx wrangler d1 create nethead-catalog` and `npx wrangler d1 create nethead-notes`;
   paste the two ids into `wrangler.toml`.
3. `npm run migrate` (the notes schema), then from `tools/catalog-pipeline`:
   `make d1` (the catalog). **This uses up the free tier's whole daily D1 write
   allowance** (the FTS index writes far more internal rows than the ~65k table
   rows), so for the rest of that UTC day every write on the site — sign-ups,
   notes, shelves — fails with "exceeded D1's free tier daily row write limit".
   Reads keep working. Push the catalog when nobody needs to write, and expect
   sign-ups to work again after midnight UTC. Once per catalog build.
4. `npm run deploy`. The site is at `https://nethead.nethead-web.workers.dev`.
5. Right after the first catalog push, check the search index took:
   `npx wrangler d1 execute nethead-catalog --remote --command "SELECT rowid FROM show_fts WHERE show_fts MATCH '\"5-8-77\"*'"`.
   If D1 refuses the contentless FTS5 table, set `SEARCH_MODE = "like"` in `wrangler.toml` — search then scans `web_search_blob`, 2,073 rows, still instant.
6. Set `ADMIN_HANDLES` in `wrangler.toml` to the handle you'll sign up with
   (the `RDVAX` node is reserved for it), redeploy, then get on the bus like any head.

CI (`.github/workflows/web.yml`) runs the tests on every change under `web/`,
and deploys on a push to `main` only if `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID` are set as repo secrets (an API token with the
"Edit Cloudflare Workers" template plus D1 edit). Without them it warns and skips.

## Passkeys and the domain

Passkeys are bound to the host name. Moving from `workers.dev` to a real domain
later invalidates every passkey minted before the move; the `ceremonies.kind`
column has room for a `handoff` ceremony (signed-in on the old host → one-time
link → new passkey on the new host), and recovery codes work across the move
regardless. Buy the domain before inviting many heads, or plan the handoff.

## Probing the live site

`node --experimental-strip-types scripts/live-signup.mjs [origin]` runs a whole
sign-up with the tests' software authenticator against a live host under a
throwaway `TEST::PROBE####` handle, prints each step's status, and leaves the bus
again. JSON routes answer a 500 with the exception in `detail`, so this is the
quickest way to see why a ceremony fails in production.

## Where things are

```
src/index.tsx        the app: secure headers → csrf → session → routes; scheduled() → cron purge
src/fmt.ts           every date, time and number: prettyDate (5/8/77), noteStamp (08-MAY-1994 09:12), the .txt formatters
src/catalog/         queries over the catalog, FTS search (+ LIKE fallback), setlist ↔ tape alignment, famous runs
src/archive/         which files are the tracks (mirrors the app's ArchiveAPIClient), archive.org metadata via the Cache API
src/auth/            handles, passkeys (@simplewebauthn/server), sessions, recovery codes, same-origin guard
src/notes/           topic numbering, note rate limits, the conference routes
src/tapes/           shelves, mix tapes, journal — rows shaped like the iOS models, with updated_at/deleted_at/seq for a later sync
src/trees/ src/lot/  trees and the lot
src/admin/           the back room
src/views/           hono/jsx pages; frame.tsx is the page frame, parts.tsx the shared bits
public/deck.js       the tape deck: fetch-and-swap navigation + two <audio> elements + Media Session
public/bus.js        the four passkey ceremonies
migrations/          the notes schema (wrangler d1 migrations)
test/                vitest-pool-workers; softauth.ts is a software authenticator that drives the real ceremonies
```

The catalog export lives in `tools/catalog-pipeline/pipeline/stage7_d1.py`
(`make d1-sql`, `make d1`, `make d1-local`, `make d1-fixture`). The knowledge
base JSON is imported straight from `ShakedownAI/Resources/knowledge_base/`, so
there is one copy.

Every string follows `VOICE.md`. The look is `docs/nethead.html`'s: mono for
anything a head would have typed, serif for anything we say to them.
