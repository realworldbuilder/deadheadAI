"""Stage 2b: fetch each tape's file list so the catalog can carry its
tracks — titles and running times — for the tapes the app actually reaches
for (the top few per show by quality score). That's what lets the home
shelf and CarPlay pin a run to a tape and say "26 min" with no network.

Caches one slim JSON per identifier under cache/tracks/ (mp3 files only:
name, format, title, track, length). Resume-safe. Needs out/catalog.sqlite
from `make build` for the per-show ranking.

Usage: python stage2b_tracks.py [--per-show K] [--limit N] [--only id1,id2]
"""
import json
import sqlite3
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

from stage2_metadata import _throttled_fetch
from tracks import is_mp3ish
from util import CACHE, OUT, write_json

PER_SHOW = 4
# The /files endpoint is slow per request (~5 s), so it takes more workers
# than stage 2 to reach the shared 4 req/s cap the rate limiter enforces.
WORKERS = 16
# Dates the test fixture is built from — fetch these first so `make fixture`
# carries tracks even from a partial crawl.
FIXTURE_DATES = {
    "1977-05-08", "1972-05-04", "1969-02-27", "1970-02-13", "1989-07-07", "1995-07-09",
    "1966-01-08", "1978-04-24", "1985-06-24", "1990-03-29", "1974-06-28", "1982-04-06",
}


def wanted_identifiers(per_show: int) -> list[str]:
    """Top tapes per show, best first; fixture nights first, then the nights
    people listen to most, so a partial crawl still covers what matters."""
    db = sqlite3.connect(OUT / "catalog.sqlite")
    rows = db.execute("""
        SELECT r.identifier, r.show_id, s.date, s.total_reviews, r.quality_score
        FROM recordings r JOIN shows s ON s.show_id = r.show_id
        ORDER BY r.show_id, r.quality_score DESC
        """).fetchall()
    db.close()
    per: dict[str, list] = {}
    for ident, show_id, date, reviews, score in rows:
        bucket = per.setdefault(show_id, [])
        if len(bucket) < per_show:
            bucket.append((ident, date, reviews, len(bucket)))
    flat = [item for bucket in per.values() for item in bucket]
    flat.sort(key=lambda t: (t[1] not in FIXTURE_DATES, t[3], -(t[2] or 0), t[0]))
    return [t[0] for t in flat]


def slim_files(raw: dict) -> list[dict]:
    files = raw.get("result") if isinstance(raw, dict) and "result" in raw else raw.get("files", raw)
    out = []
    for f in files or []:
        if not isinstance(f, dict) or not f.get("name"):
            continue
        if is_mp3ish(f):
            out.append({k: f.get(k) for k in ("name", "format", "title", "track", "length") if f.get(k) is not None})
    return out


def main() -> None:
    args = sys.argv[1:]
    per_show = int(args[args.index("--per-show") + 1]) if "--per-show" in args else PER_SHOW
    limit = int(args[args.index("--limit") + 1]) if "--limit" in args else None
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else None

    idents = wanted_identifiers(per_show)
    if only is not None:
        idents = [i for i in idents if i in only]
    tracks_dir = CACHE / "tracks"
    tracks_dir.mkdir(parents=True, exist_ok=True)
    todo = [i for i in idents if not (tracks_dir / f"{i}.json").exists()]
    cached = len(idents) - len(todo)
    if limit is not None:
        todo = todo[:limit]
    print(f"stage2b: {len(idents)} wanted, {cached} cached, {len(todo)} to fetch", file=sys.stderr)

    errors = 0

    def grab(ident: str) -> str:
        raw = json.loads(_throttled_fetch(f"https://archive.org/metadata/{ident}/files"))
        write_json(tracks_dir / f"{ident}.json", slim_files(raw))
        return ident

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {pool.submit(grab, ident): ident for ident in todo}
        for n, future in enumerate(as_completed(futures), 1):
            try:
                future.result()
            except Exception as e:  # noqa: BLE001 — log and continue; build tolerates gaps
                errors += 1
                print(f"stage2b: FAILED {futures[future]}: {e}", file=sys.stderr)
            if n % 250 == 0:
                print(f"stage2b: {n}/{len(todo)}", file=sys.stderr)
    print(f"stage2b: done, {errors} errors")


if __name__ == "__main__":
    main()
