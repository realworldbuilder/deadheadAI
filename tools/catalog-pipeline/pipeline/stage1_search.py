"""Stage 1: list every item in collection:GratefulDead via the scrape API.

Output: out/items.json — [{identifier, date, venue, coverage, title,
avg_rating, num_reviews, downloads, source}, ...]
Raw cursor pages cached under cache/search/.
"""
import json
import re
import sys
import urllib.parse

from util import CACHE, OUT, fetch, read_json, write_json

FIELDS = "identifier,date,venue,coverage,title,avg_rating,num_reviews,downloads,source"
BASE = "https://archive.org/services/search/v1/scrape"

DATE_RE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})")


def crawl(force: bool = False) -> list[dict]:
    pages_dir = CACHE / "search"
    pages_dir.mkdir(parents=True, exist_ok=True)
    items: list[dict] = []
    cursor = None
    page = 0
    while True:
        page_path = pages_dir / f"page_{page:04d}.json"
        if page_path.exists() and not force:
            data = read_json(page_path)
        else:
            qs = {"q": "collection:GratefulDead", "count": "10000", "fields": FIELDS}
            if cursor:
                qs["cursor"] = cursor
            url = f"{BASE}?{urllib.parse.urlencode(qs)}"
            print(f"stage1: fetching page {page}...", file=sys.stderr)
            data = json.loads(fetch(url))
            write_json(page_path, data)
        items.extend(data.get("items", []))
        cursor = data.get("cursor")
        page += 1
        if not cursor:
            break
    return items


def clean(items: list[dict]) -> list[dict]:
    """Keep items with a parseable 1965–1995 date; normalize the date field."""
    out = []
    seen = set()
    for it in items:
        ident = it.get("identifier")
        if not ident or ident in seen:
            continue
        m = DATE_RE.match(it.get("date") or "")
        if not m:
            continue
        year = int(m.group(1))
        if not (1965 <= year <= 1995):
            continue
        month, day = int(m.group(2)), int(m.group(3))
        if not (1 <= month <= 12 and 1 <= day <= 31):
            continue
        seen.add(ident)
        out.append({
            "identifier": ident,
            "date": f"{year:04d}-{month:02d}-{day:02d}",
            "venue": it.get("venue"),
            "coverage": it.get("coverage"),
            "title": it.get("title"),
            "avg_rating": it.get("avg_rating"),
            "num_reviews": it.get("num_reviews"),
            "downloads": it.get("downloads"),
            "source": it.get("source"),
        })
    out.sort(key=lambda x: (x["date"], x["identifier"]))
    return out


def main() -> None:
    raw = crawl(force="--force" in sys.argv)
    cleaned = clean(raw)
    write_json(OUT / "items.json", cleaned)
    print(f"stage1: {len(raw)} raw items, {len(cleaned)} dated 1965-1995")


if __name__ == "__main__":
    main()
