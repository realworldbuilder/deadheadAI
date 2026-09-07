"""Ticket stubs, backstage passes & posters from jerrygarcia.com (robots.txt permits).

The Yoast sitemaps list every show URL with the date in the slug, so no
index crawling: map our catalog dates onto show pages, fetch each page
once (cached under cache/jgimages/, gitignored), and parse its galleries.

A show page carries two carousels:
  rel="ticket_gallery"  the Ticket Archive — ticket scans and backstage
                        passes, aspect-true "large" renditions.
  rel="show_images"     the fan "Photos" carousel — posters live only
                        here, next to venue snapshots. We keep the poster
                        (and ticket) entries and drop the snapshots; the
                        thumbnails are square crops, so no dimensions.

We store URLs only and hotlink at runtime — no scans are redistributed.

Output: cache/jgimages/gallery.json
            {"1977-05-08": [{"url": ..., "kind": "ticket", "width": 319, "height": 157}, ...]}
        cache/jgimages/index.json   {"1977-05-08": "https://cdn...jpg"}   (first gallery URL, "" when none)

Usage: python stage_images.py [--limit N] [--offline]
  --offline never touches the network: pages missing from the cache are skipped.
"""
import json
import re
import sys
from pathlib import Path

from util import CACHE, OUT, fetch, read_json, write_json

BASE = "https://jerrygarcia.com"
SLUG_DATE_RE = re.compile(r"/show/((\d{4})-(\d{2})-(\d{2})-([a-z0-9-]+))/")
# Photos-carousel anchors put their <img> on the next line; the Ticket
# Archive keeps it inline.
ANCHOR_IMG_RE = re.compile(r"<a\b([^>]*)>\s*<img\b([^>]*)>", re.S)
REL_RE = re.compile(r'rel="([^"]+)"')
DATA_LINK_RE = re.compile(r'data-link="(https://jerrygarcia\.com/image/[^"]+)"')
HREF_CDN_RE = re.compile(r'href="(https://cdn\.jerrygarcia\.com/[^"]+)"')
WIDTH_RE = re.compile(r'\bwidth="(\d+)"')
HEIGHT_RE = re.compile(r'\bheight="(\d+)"')

IMG_DIR = CACHE / "jgimages"

TICKET_ARCHIVE = "ticket_gallery"
PHOTOS = "show_images"

KIND_RANK = {"ticket": 0, "poster": 1, "backstage_pass": 2, "other": 3}


def show_urls() -> list[str]:
    urls: list[str] = []
    for suffix in ("", "2", "3", "4"):
        path = IMG_DIR / f"show-sitemap{suffix or '1'}.xml"
        if path.exists():
            xml = path.read_text()
        else:
            xml = fetch(f"{BASE}/show-sitemap{suffix}.xml").decode("utf-8", "replace")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(xml)
        urls += re.findall(r"<loc>(https://jerrygarcia\.com/show/[^<]+)</loc>", xml)
    return urls


def venue_tokens(text: str) -> set[str]:
    return {t for t in re.split(r"[^a-z0-9]+", text.lower()) if len(t) > 3}


def classify(slug: str) -> str:
    """Image-page slug -> kind. Backstage first: a pass slug never says
    "ticket", but check it first anyway so a combined slug can't misfile."""
    s = slug.rstrip("/").rsplit("/", 1)[-1].lower()
    if "backstage" in s or "stage-pass" in s:
        return "backstage_pass"
    if "poster" in s:
        return "poster"
    if "ticket" in s or "stub" in s:
        return "ticket"
    return "other"


def gallery_items(html: str) -> list[dict]:
    """Every gallery anchor on the page, in document order, tolerant of
    attribute order: {rel, slug, url, width, height, doc_index}."""
    items = []
    for anchor, img in ANCHOR_IMG_RE.findall(html):
        link = DATA_LINK_RE.search(anchor)
        cdn = HREF_CDN_RE.search(anchor)
        rel = REL_RE.search(anchor)
        if not (link and cdn):
            continue
        w = WIDTH_RE.search(img)
        h = HEIGHT_RE.search(img)
        items.append({
            "rel": rel.group(1) if rel else "",
            "slug": link.group(1),
            "url": cdn.group(1),
            "width": int(w.group(1)) if w else None,
            "height": int(h.group(1)) if h else None,
            "doc_index": len(items),
        })
    return items


def memorabilia(items: list[dict]) -> list[dict]:
    """The scans we show: the whole Ticket Archive, plus poster/ticket
    entries from the Photos carousel (fan snapshots dropped). Ordered
    ticket -> poster -> backstage pass -> other, document order within a
    kind, so the first entry is the cover (the legacy pick_image rule)."""
    kept = []
    for it in items:
        kind = classify(it["slug"])
        if it["rel"] == TICKET_ARCHIVE:
            width, height = it["width"], it["height"]
        elif it["rel"] == PHOTOS and kind in ("poster", "ticket"):
            width, height = None, None  # square-cropped thumbnails
        else:
            continue
        kept.append({"url": it["url"], "kind": kind, "width": width, "height": height,
                     "_rank": KIND_RANK[kind], "_doc": it["doc_index"]})
    kept.sort(key=lambda k: (k["_rank"], k["_doc"]))
    seen: set[str] = set()
    out = []
    for k in kept:
        if k["url"] in seen:
            continue
        seen.add(k["url"])
        out.append({"url": k["url"], "kind": k["kind"], "width": k["width"], "height": k["height"]})
    return out


def pick_image(html: str) -> str | None:
    """The cover: first entry of the ordered memorabilia list."""
    found = memorabilia(gallery_items(html))
    return found[0]["url"] if found else None


def main() -> None:
    limit = None
    if "--limit" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--limit") + 1])
    offline = "--offline" in sys.argv

    # Dates we care about: every show in the built catalog.
    import sqlite3
    db = sqlite3.connect(OUT / "catalog.sqlite")
    wanted = {row[0]: (row[1] or "") for row in
              db.execute("SELECT date, venue FROM shows")}

    by_date: dict[str, list[tuple[str, str]]] = {}
    for url in show_urls():
        m = SLUG_DATE_RE.search(url)
        if not m:
            continue
        date = f"{m.group(2)}-{m.group(3)}-{m.group(4)}"
        if date in wanted:
            by_date.setdefault(date, []).append((url, m.group(5)))

    # Both outputs are rebuilt from scratch every run: resume-safety comes
    # from the page cache, not from the previous index.
    gallery: dict[str, list[dict]] = {}
    index: dict[str, str] = {}
    fetched = 0
    skipped = 0
    for date, candidates in sorted(by_date.items()):
        # Same-date pages (e.g. a JGB gig elsewhere): prefer the slug that
        # shares venue words with our catalog row.
        ours = venue_tokens(wanted[date])
        candidates.sort(key=lambda c: len(ours & venue_tokens(c[1])), reverse=True)
        url, _ = candidates[0]
        # Cache by the full slug (date included) — venue alone collides
        # across the many nights at the same hall.
        slug = SLUG_DATE_RE.search(url).group(1)
        page_path = IMG_DIR / f"{slug}.html"
        try:
            if page_path.exists():
                html = page_path.read_text(errors="replace")
            elif offline or (limit is not None and fetched >= limit):
                skipped += 1
                continue
            else:
                html = fetch(url).decode("utf-8", "replace")
                page_path.write_text(html)
                fetched += 1
                if fetched % 100 == 0:
                    print(f"stage_images: fetched {fetched} pages", file=sys.stderr)
            found = memorabilia(gallery_items(html))
            gallery[date] = found
            index[date] = found[0]["url"] if found else ""
        except Exception as e:  # noqa: BLE001
            print(f"stage_images: FAILED {url}: {e}", file=sys.stderr)
    write_json(IMG_DIR / "gallery.json", gallery)
    write_json(IMG_DIR / "index.json", index)

    with_image = sum(1 for v in gallery.values() if v)
    kinds: dict[str, int] = {}
    for scans in gallery.values():
        for s in scans:
            kinds[s["kind"]] = kinds.get(s["kind"], 0) + 1
    print(f"stage_images: {len(gallery)} dates resolved ({fetched} fetched, {skipped} uncached skipped), "
          f"{with_image} with scans, {sum(kinds.values())} images "
          + json.dumps(kinds, sort_keys=True))


if __name__ == "__main__":
    main()
