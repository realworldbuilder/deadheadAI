# Catalog pipeline

Builds `ShakedownAI/Resources/catalog/catalog.sqlite` — the bundled, offline
catalog of every Grateful Dead show (1965–1995): real setlists with sets,
encores, and segues; every archive.org tape with detected source type
(SBD/MTX/FM/AUD) and a precomputed quality ranking; and optional AI review
digests. The app reads it through `Core/Catalog/` and falls back to live
archive.org queries for anything the catalog doesn't know.

## Sources

- **archive.org** — the [scrape API](https://archive.org/services/search/v1/scrape)
  lists the `GratefulDead` collection (~18k items); `/metadata/{id}` supplies
  lineage, taper, per-item setlist text, and full review bodies.
- **cs.cmu.edu/~mleone/gdead** — the classic plain-text setlist archive,
  1972–1995. Unmaintained but static for decades; every fetched file is
  cached under `cache/setlists/` (commit it, so the pipeline can rebuild
  forever without the origin). Pre-1972 setlists fall back to archive.org's
  per-item `setlist` field (`setlist_status = partial`).
- **jerrygarcia.com** — the Ticket Archive (ticket scans, backstage passes)
  and the poster entries of each show page's Photos carousel (fan venue
  snapshots are skipped). URLs only, hotlinked at runtime — no scan is
  redistributed. Fetched show pages are cached under `cache/jgimages/`
  (gitignored — they are verbatim copies of another site); only the two
  derived, URL-only indexes (`gallery.json`, `index.json`) are committed,
  which is all `make build` needs. `make images` refetches the pages.

We copy no third-party app's data or code; setlists are facts, ratings math
and source detection are reimplemented here (see `sourcetype.py`,
`stage4_build.py`).

## Running

```bash
make crawl      # stage 1: list the collection (minutes)
make setlists   # stage 3: CMU setlists (cached after first run)
make metadata   # stage 2: per-item metadata, 8 workers @ ~5 req/s (~1h cold, resume-safe)
make build      # stage 4: emit out/catalog.sqlite + build report with regression gates
make tracks     # stage 2b: file lists for the top 4 tapes per show (~7k items, ~30 min cold, resume-safe), then rebuild
make images     # jerrygarcia.com galleries -> cache/jgimages/gallery.json, then re-embeds (offline)
make digests    # stage 5: AI review digests — optional, maintainers only, needs OPENAI_API_KEY; the output is committed under cache/digests/ so nobody needs the key to build
make fixture    # small catalog for ShakedownAITests
make install    # copy out/catalog.sqlite into the app bundle resources
make test       # pytest over parsers/scorer/detection
```

After `make install`, run `xcodegen generate` at the repo root so the new
resource is picked up, and re-run the app tests.

Crawl etiquette: descriptive User-Agent with contact email, shared rate
limiter, exponential backoff, resume-safe cache — re-runs only fetch new
uploads. Run it manually (monthly-ish); never wire it into CI on push.

## Versioning

`catalog_meta` carries `schema_version` (the app refuses mismatches and
falls back to network-only), `generated_at`, counts, and the git commit.
Settings → About surfaces the stamp. Bump `SCHEMA_VERSION` in
`stage4_build.py` *and* `expectedSchemaVersion` in
`ShakedownAI/Core/Catalog/CatalogDB.swift` together. Schema 2 added
`show_images` (every memorabilia scan per date, position 0 == the show's
`cover_image_url`). Schema 3 added `recording_tracks` (stage 2b): for the top
four tapes per show, the tape's tracks as compact `[title, seconds, file]`
triples in play order, selected and titled exactly as the app's live detail
call would (`tracks.py` mirrors `ArchiveAPIClient`), so runs resolve and
show their running time with no network. The `git_commit` stamp is the HEAD the build ran on,
i.e. the commit *before* the one that lands the rebuilt catalog.
