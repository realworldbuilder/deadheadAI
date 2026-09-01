"""Stage 2: fetch archive.org /metadata/{identifier} for every item.

Caches one JSON per identifier under cache/metadata/ with the `files`
array stripped (we only need metadata + reviews). Resume-safe: already
cached identifiers are skipped, so re-runs only fetch new uploads.

Usage: python stage2_metadata.py [--only id1,id2,...] [--limit N]
"""
import json
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

from util import CACHE, OUT, USER_AGENT, read_json, write_json

WORKERS = 6
RPS = 4.0  # shared across workers

_rate_lock = threading.Lock()
_next_slot = [0.0]


def _throttled_fetch(url: str, retries: int = 4) -> bytes:
    """Thread-safe token-spaced GET: at most RPS requests/second overall."""
    delay = 1.0
    for attempt in range(retries + 1):
        with _rate_lock:
            now = time.monotonic()
            wait = _next_slot[0] - now
            _next_slot[0] = max(now, _next_slot[0]) + 1.0 / RPS
        if wait > 0:
            time.sleep(wait)
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return resp.read()
        except Exception:  # noqa: BLE001
            if attempt < retries:
                time.sleep(delay)
                delay *= 2
                continue
            raise
    raise RuntimeError(f"unreachable: {url}")

KEEP_METADATA = [
    "identifier", "date", "venue", "coverage", "title", "source",
    "lineage", "taper", "transferer", "setlist", "notes", "description",
]


def slim(raw: dict) -> dict:
    md = raw.get("metadata", {}) or {}
    return {
        "metadata": {k: md.get(k) for k in KEEP_METADATA if md.get(k) is not None},
        "reviews": [
            {k: r.get(k) for k in ("reviewbody", "reviewtitle", "reviewer", "reviewdate", "stars")}
            for r in (raw.get("reviews") or [])
        ],
    }


def main() -> None:
    args = sys.argv[1:]
    only = None
    limit = None
    if "--only" in args:
        only = set(args[args.index("--only") + 1].split(","))
    if "--limit" in args:
        limit = int(args[args.index("--limit") + 1])

    items = read_json(OUT / "items.json")
    idents = [it["identifier"] for it in items]
    if only is not None:
        idents = [i for i in idents if i in only]

    meta_dir = CACHE / "metadata"
    meta_dir.mkdir(parents=True, exist_ok=True)
    # Review-rich items first: they carry the digests and the lineage of the
    # tapes people actually play, so a partial crawl still builds well.
    weight = {it["identifier"]: (it.get("num_reviews") or 0, it.get("downloads") or 0)
              for it in items}
    idents.sort(key=lambda i: weight.get(i, (0, 0)), reverse=True)
    todo = [i for i in idents if not (meta_dir / f"{i}.json").exists()]
    if limit is not None:
        todo = todo[:limit]
    print(f"stage2: {len(idents)} wanted, {len(idents) - len(todo)} cached, {len(todo)} to fetch", file=sys.stderr)

    errors = 0

    def grab(ident: str) -> str | None:
        raw = json.loads(_throttled_fetch(f"https://archive.org/metadata/{ident}"))
        write_json(meta_dir / f"{ident}.json", slim(raw))
        return ident

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {pool.submit(grab, ident): ident for ident in todo}
        for n, future in enumerate(as_completed(futures), 1):
            try:
                future.result()
            except Exception as e:  # noqa: BLE001 — log and continue; build tolerates gaps
                errors += 1
                print(f"stage2: FAILED {futures[future]}: {e}", file=sys.stderr)
            if n % 500 == 0:
                print(f"stage2: {n}/{len(todo)}", file=sys.stderr)
    print(f"stage2: done, {errors} errors")


if __name__ == "__main__":
    main()
