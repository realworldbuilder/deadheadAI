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

We copy no third-party app's data or code; setlists are facts, ratings math
and source detection are reimplemented here (see `sourcetype.py`,
`stage4_build.py`).

## Running

```bash
make crawl      # stage 1: list the collection (minutes)
make setlists   # stage 3: CMU setlists (cached after first run)
make metadata   # stage 2: per-item metadata, 8 workers @ ~5 req/s (~1h cold, resume-safe)
make build      # stage 4: emit out/catalog.sqlite + build report with regression gates
make digests    # stage 5: AI review digests (needs OPENAI_API_KEY), then re-embeds
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
`ShakedownAI/Core/Catalog/CatalogDB.swift` together.
