"""Ticket stubs & show imagery from jerrygarcia.com (robots.txt permits).

The Yoast sitemaps list every show URL with the date in the slug, so no
index crawling: map our catalog dates onto show pages, fetch each page
once (cached), and pull the gallery's ticket scan (anchor whose
data-link ends in "-ticket/"), falling back to the first gallery image.
We store URLs only and hotlink at runtime — no scans are redistributed.

Output: cache/jgimages/index.json {"1977-05-08": "https://cdn...jpg"}

Usage: python stage_images.py [--limit N]
"""
import json
import re
import sys
from pathlib import Path

from util import CACHE, OUT, fetch, read_json, write_json

BASE = "https://jerrygarcia.com"
SLUG_DATE_RE = re.compile(r"/show/((\d{4})-(\d{2})-(\d{2})-([a-z0-9-]+))/")
ANCHOR_RE = re.compile(r"<a\b[^>]*>")
DATA_LINK_RE = re.compile(r'data-link="(https://jerrygarcia\.com/image/[^"]+)"')
HREF_CDN_RE = re.compile(r'href="(https://cdn\.jerrygarcia\.com/[^"]+)"')

IMG_DIR = CACHE / "jgimages"


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


def gallery_items(html: str) -> list[tuple[str, str]]:
    """(image-page slug URL, CDN image URL) for every gallery anchor,
    tolerant of attribute order."""
    items = []
    for anchor in ANCHOR_RE.findall(html):
        link = DATA_LINK_RE.search(anchor)
        cdn = HREF_CDN_RE.search(anchor)
        if link and cdn:
            items.append((link.group(1), cdn.group(1)))
    return items


def pick_image(html: str) -> str | None:
    """Ticket scan first (deadly's ordering), then poster, then anything."""
    items = gallery_items(html)
    for link, cdn in items:
        if "-ticket" in link.rstrip("/").rsplit("/", 1)[-1]:
            return cdn
    for link, cdn in items:
        if "poster" in link:
            return cdn
    return items[0][1] if items else None


def main() -> None:
    limit = None
    if "--limit" in sys.argv:
        limit = int(sys.argv[sys.argv.index("--limit") + 1])

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

    index_path = IMG_DIR / "index.json"
    index: dict[str, str] = read_json(index_path) if index_path.exists() else {}

    done = 0
    for date, candidates in sorted(by_date.items()):
        if date in index:
            continue
        if limit is not None and done >= limit:
            break
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
            else:
                html = fetch(url).decode("utf-8", "replace")
                page_path.write_text(html)
            image = pick_image(html)
            index[date] = image or ""
            done += 1
            if done % 100 == 0:
                write_json(index_path, index)
                print(f"stage_images: {done} pages, {sum(1 for v in index.values() if v)} images",
                      file=sys.stderr)
        except Exception as e:  # noqa: BLE001
            print(f"stage_images: FAILED {url}: {e}", file=sys.stderr)
    write_json(index_path, index)
    with_image = sum(1 for v in index.values() if v)
    tickets = sum(1 for v in index.values() if "/t" in v.rsplit("/", 1)[-1][:2] or "ticket" in v)
    print(f"stage_images: {len(index)} dates resolved, {with_image} with an image ({tickets} look like tickets)")


if __name__ == "__main__":
    main()
