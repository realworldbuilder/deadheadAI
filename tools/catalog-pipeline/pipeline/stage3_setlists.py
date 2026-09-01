"""Stage 3: setlists from the cs.cmu.edu Grateful Dead archive (1972-1995).

The archive is one HTML index per year linking one plain-text file per
show. Format of the text files:

    Venue, City, ST (M/D/YY)
    <blank>
    Song            } set 1
    ...
    <blank>
    Song            } set 2
    ...
    <blank>
    Song            } encore (last block, short)

There are no segue markers; segues are recovered later (stage 4) from
archive.org setlist text where available. Raw fetches are cached under
cache/setlists/ — commit that directory so the pipeline can rebuild
forever without the (unmaintained) origin site.

Output: out/setlists.json — {"YYYY-MM-DD" or "YYYY-MM-DD-early|late":
  {date, venue, city, state, blocks: [[title, ...], ...], source: "cmu"}}
"""
import re
import sys

from util import CACHE, OUT, fetch, write_json

BASE = "https://www.cs.cmu.edu/~mleone/gdead"
YEARS = list(range(72, 96))  # 1972-1995

LINK_RE = re.compile(
    r'<a href="(dead-sets/[^"]+\.txt)">\s*([^<]+?)\s*</a>', re.I | re.S
)
# Some headers carry a weekday: "(Sunday, 1/24/93)".
HEADER_DATE_RE = re.compile(r"\((?:[A-Za-z]+,?\s*)?(\d{1,2})/(\d{1,2})/(\d{2})\)")
SEGUE_TAIL_RE = re.compile(r"\s*(?:-+>|>)\s*$")
EARLY_RE = re.compile(r"\bearly\b", re.I)
LATE_RE = re.compile(r"\blate\b", re.I)


def _cached_fetch(rel_path: str) -> str:
    path = CACHE / "setlists" / rel_path.replace("/", "_")
    if path.exists():
        return path.read_text(errors="replace")
    text = fetch(f"{BASE}/{rel_path}").decode("utf-8", errors="replace")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return text


def parse_show_file(text: str) -> dict | None:
    """Header line + blank-separated song blocks.

    Each block entry is [title, segues_into_next]: 90s-era files mark
    segues with a trailing "->"; older files have no markers (flag 0).
    """
    lines = [ln.rstrip() for ln in text.splitlines()]
    # find header: first non-empty line containing a (M/D/YY) date
    header_idx = None
    for i, ln in enumerate(lines):
        if ln.strip() and HEADER_DATE_RE.search(ln):
            header_idx = i
            break
    if header_idx is None:
        return None
    header = lines[header_idx].strip()
    m = HEADER_DATE_RE.search(header)
    month, day, yy = int(m.group(1)), int(m.group(2)), int(m.group(3))
    year = 1900 + yy
    date = f"{year:04d}-{month:02d}-{day:02d}"

    place = header[: m.start()].strip().rstrip(",").strip()
    venue, city, state = place, None, None
    parts = [p.strip() for p in place.split(",")]
    if len(parts) >= 3:
        venue, city, state = ", ".join(parts[:-2]), parts[-2], parts[-1]
    elif len(parts) == 2:
        venue, city = parts

    blocks: list[list] = []
    current: list = []
    for ln in lines[header_idx + 1:]:
        s = ln.strip()
        if not s:
            if current:
                blocks.append(current)
                current = []
            continue
        # skip credit/comment lines occasionally appended
        if s.startswith(("(", "*", "?", "--")) or s.lower().startswith(("thanks", "note:", "source:")):
            continue
        segue = bool(SEGUE_TAIL_RE.search(s))
        title = SEGUE_TAIL_RE.sub("", s).strip()
        if title:
            current.append([title, int(segue)])
    if current:
        blocks.append(current)
    if not blocks:
        return None
    return {"date": date, "venue": venue, "city": city, "state": state, "blocks": blocks}


def main() -> None:
    setlists: dict[str, dict] = {}
    date_counts: dict[str, int] = {}
    failures = 0
    for yy in YEARS:
        index_html = _cached_fetch(f"{yy}.html")
        links = LINK_RE.findall(index_html)
        print(f"stage3: 19{yy}: {len(links)} shows", file=sys.stderr)
        for rel, label in links:
            try:
                parsed = parse_show_file(_cached_fetch(rel))
            except Exception as e:  # noqa: BLE001
                print(f"stage3: FAILED {rel}: {e}", file=sys.stderr)
                failures += 1
                continue
            if parsed is None:
                print(f"stage3: unparseable {rel}", file=sys.stderr)
                failures += 1
                continue
            parsed["source"] = "cmu"
            date = parsed["date"]
            n = date_counts.get(date, 0)
            if n == 0:
                key = date
            else:
                # second file for the same date: early/late pair. Re-key the
                # first as -early (or per its label) and this one as -late.
                if date in setlists:
                    setlists[f"{date}-early"] = setlists.pop(date)
                key = f"{date}-late" if not EARLY_RE.search(label) else f"{date}-early"
                if key in setlists:
                    key = f"{date}-late" if key.endswith("-early") else f"{date}-early"
            date_counts[date] = n + 1
            setlists[key] = parsed
    write_json(OUT / "setlists.json", setlists)
    doubles = sum(1 for c in date_counts.values() if c > 1)
    print(f"stage3: {len(setlists)} setlists, {doubles} early/late dates, {failures} failures")


if __name__ == "__main__":
    main()
