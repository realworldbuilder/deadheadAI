"""Stage 4: build catalog.sqlite from the cached crawl + setlists.

Usage:
    python stage4_build.py [--out PATH] [--fixture d1,d2,...] [--no-gates]

--fixture builds a small db restricted to the given dates and skips the
regression gates (used for the app's test fixture).
"""
import bisect
import json
import math
import re
import sqlite3
import subprocess
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

import fts
import songcanon
import sourcetype
import tracks
from util import CACHE, OUT, read_json

SCHEMA_VERSION = 3

ERAS = [
    ("primal", 1965, 1967), ("anthem", 1968, 1970), ("europe-wall", 1971, 1974),
    ("hiatus-return", 1975, 1977), ("transition", 1978, 1979),
    ("brent", 1980, 1990), ("vince", 1991, 1995),
]

LATE_ID_RE = re.compile(r"\blate\b|\.late\.|_late", re.I)

# Misspellings in the CMU source data, fixed at build time.
PLACE_FIXES = {"Ithica": "Ithaca", "Sacremento": "Sacramento", "Pittsburg": "Pittsburgh"}

SCHEMA = """
CREATE TABLE catalog_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE shows(
  show_id TEXT PRIMARY KEY,
  date TEXT NOT NULL,
  year INTEGER NOT NULL, month INTEGER NOT NULL, day INTEGER NOT NULL,
  era_id TEXT,
  venue TEXT, city TEXT, state TEXT,
  setlist_status TEXT NOT NULL,
  recording_count INTEGER NOT NULL,
  best_identifier TEXT,
  best_source_type TEXT,
  avg_rating REAL, total_reviews INTEGER NOT NULL, total_downloads INTEGER NOT NULL,
  cover_image_url TEXT
);
CREATE INDEX idx_shows_ymd ON shows(year, month, day);
CREATE INDEX idx_shows_monthday ON shows(month, day);
CREATE INDEX idx_shows_venue ON shows(venue);
CREATE TABLE show_images(
  date TEXT NOT NULL,
  position INTEGER NOT NULL,
  kind TEXT NOT NULL,
  url TEXT NOT NULL,
  width INTEGER, height INTEGER,
  PRIMARY KEY(date, position)
);
CREATE TABLE recordings(
  identifier TEXT PRIMARY KEY,
  show_id TEXT NOT NULL REFERENCES shows(show_id),
  title TEXT, source_type TEXT NOT NULL,
  source_text TEXT, lineage TEXT, taper TEXT,
  avg_rating REAL, num_reviews INTEGER NOT NULL, downloads INTEGER NOT NULL,
  quality_score REAL NOT NULL
);
CREATE INDEX idx_recordings_show ON recordings(show_id, quality_score DESC);
CREATE TABLE recording_tracks(
  identifier TEXT PRIMARY KEY REFERENCES recordings(identifier),
  tracks_json TEXT NOT NULL
);
CREATE TABLE setlist_entries(
  show_id TEXT NOT NULL REFERENCES shows(show_id),
  position INTEGER NOT NULL,
  set_label TEXT NOT NULL,
  song_key TEXT NOT NULL,
  song_title TEXT NOT NULL,
  segues_into_next INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(show_id, position)
);
CREATE INDEX idx_setlist_song ON setlist_entries(song_key, show_id);
CREATE TABLE songs(
  song_key TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  times_played INTEGER NOT NULL,
  first_played TEXT, last_played TEXT
);
CREATE TABLE song_aliases(
  variant_key TEXT PRIMARY KEY,
  canonical_key TEXT NOT NULL
);
CREATE TABLE ai_digest(
  show_id TEXT PRIMARY KEY REFERENCES shows(show_id),
  consensus_summary TEXT NOT NULL,
  standout_songs_json TEXT NOT NULL,
  sentiment TEXT NOT NULL,
  derived_rating REAL NOT NULL,
  rating_rationale TEXT NOT NULL,
  model TEXT NOT NULL,
  generated_at TEXT NOT NULL
);
CREATE VIRTUAL TABLE show_fts USING fts5(blob, content='', tokenize='unicode61 remove_diacritics 2');
"""


def era_for(year: int) -> str | None:
    for era_id, lo, hi in ERAS:
        if lo <= year <= hi:
            return era_id
    return None


def quality_score(source_type: str, rating: float | None, reviews: int, downloads: int) -> float:
    """Lexicographic-ish scalar: source tier dominates, then a >=5-review
    gate, then confidence-shrunk rating, then downloads as a tiny tiebreak."""
    tier = sourcetype.TIER[source_type]          # 0 (SBD) .. 4 (UNKNOWN)
    gate = 1 if reviews >= 5 else 0
    r = rating if rating is not None else 3.0
    shrunk = (reviews * r + 5 * 3.0) / (reviews + 5)  # pulls small-n toward 3.0
    return (4 - tier) * 1000 + gate * 100 + shrunk * 10 + min(math.log10(downloads + 1), 6) / 10


def set_labels(blocks: list[list[str]]) -> list[str]:
    """Label CMU blocks: trailing short blocks are encores, the rest sets."""
    n = len(blocks)
    if n == 1:
        return ["Set 1"]
    labels = [""] * n
    encore_count = 0
    i = n - 1
    while i > 0 and len(blocks[i]) <= 2 and encore_count < 2:
        encore_count += 1
        i -= 1
    set_count = n - encore_count
    for j in range(set_count):
        labels[j] = f"Set {j + 1}"
    for j in range(encore_count):
        labels[set_count + j] = "Encore" if encore_count == 1 else ("Encore" if j == 0 else "Encore 2")
    return labels


_SETLIST_SPLIT = re.compile(r"[\n;,]+")


def parse_archive_setlist(text: str) -> list[tuple[str, bool]]:
    """Archive.org per-item `setlist` field -> [(title, segues_into_next)].
    Titles separated by '>' mark segues; commas/newlines don't."""
    out: list[tuple[str, bool]] = []
    for chunk in _SETLIST_SPLIT.split(text):
        chunk = chunk.strip()
        if not chunk:
            continue
        pieces = re.split(r"\s*(?:-+>|>)\s*", chunk)
        for i, piece in enumerate(pieces):
            title = piece.strip(" \t*-")
            if not title or len(title) > 60:
                continue
            out.append((title, i < len(pieces) - 1))
    return out


def recover_segues(entries: list[dict], archive_seq: list[tuple[str, bool]]) -> None:
    """Union segue flags from archive setlist text onto CMU entries by
    monotonic canonical-key alignment (never clears a CMU-marked segue)."""
    j = 0
    for entry in entries:
        for k in range(j, len(archive_seq)):
            if songcanon.canonical_key(archive_seq[k][0]) == entry["song_key"]:
                entry["segues_into_next"] |= int(archive_seq[k][1])
                j = k + 1
                break


def track_rows_for(identifiers) -> list[tuple[str, str]]:
    """(identifier, tracks_json) for every tape stage 2b fetched files for.
    Compact: one [title, seconds, file name] per track, play order — what the
    app needs to pin a run to a tape and say how long it is, with no network."""
    rows = []
    for ident in identifiers:
        path = CACHE / "tracks" / f"{ident}.json"
        if not path.exists():
            continue
        built = tracks.build_tracks(read_json(path))
        if not built:
            continue
        payload = [[t["title"], round(t["seconds"], 1) if t["seconds"] is not None else None, t["name"]]
                   for t in built]
        rows.append((ident, json.dumps(payload, ensure_ascii=False, separators=(",", ":"))))
    return rows


def load_metadata(identifier: str) -> dict:
    path = CACHE / "metadata" / f"{identifier}.json"
    if path.exists():
        return read_json(path)
    return {"metadata": {}, "reviews": []}


def build(out_path: Path, fixture_dates: set[str] | None, gates: bool) -> None:
    t0 = time.time()
    items = read_json(OUT / "items.json")
    setlists = read_json(OUT / "setlists.json") if (OUT / "setlists.json").exists() else {}
    # jerrygarcia.com memorabilia (see stage_images.py): every scan per
    # date, cover first. The legacy one-URL index is only a fallback so a
    # checkout without gallery.json still builds (with no show_images).
    gallery_path = CACHE / "jgimages" / "gallery.json"
    index_path = CACHE / "jgimages" / "index.json"
    if gallery_path.exists():
        gallery = read_json(gallery_path)
        legacy_covers = {}
    else:
        print("stage4: cache/jgimages/gallery.json missing — run stage_images.py; "
              "show_images will be empty", file=sys.stderr)
        gallery = {}
        legacy_covers = read_json(index_path) if index_path.exists() else {}

    if fixture_dates:
        items = [it for it in items if it["date"] in fixture_dates]

    # --- group recordings into shows -------------------------------------
    by_show: dict[str, list[dict]] = defaultdict(list)
    for it in items:
        date = it["date"]
        if f"{date}-early" in setlists or f"{date}-late" in setlists:
            show_id = f"{date}-late" if LATE_ID_RE.search(it["identifier"]) else f"{date}-early"
        else:
            show_id = date
        by_show[show_id].append(it)
    # shows that exist only in the setlist archive (no recordings) are skipped:
    # the app can't play them, and best_identifier would be null.

    show_rows, rec_rows, entry_rows, image_rows = [], [], [], []
    image_dates: set[str] = set()
    song_agg: dict[str, dict] = {}
    fts_inputs = []
    setlist_full = 0
    setlist_partial = 0

    show_downloads: dict[str, int] = {}
    for show_id, recs in by_show.items():
        show_downloads[show_id] = sum(r.get("downloads") or 0 for r in recs)
    dl_sorted = sorted(show_downloads.values())

    def dl_percentile(v: int) -> float:
        if not dl_sorted:
            return 0.0
        return bisect.bisect_left(dl_sorted, v) / len(dl_sorted)

    for show_id in sorted(by_show):
        recs = by_show[show_id]
        date = show_id[:10]
        year, month, day = int(date[:4]), int(date[5:7]), int(date[8:10])

        best = None
        source_types: set[str] = set()
        arch_setlist_texts: list[str] = []
        show_recs: list[dict] = []
        for it in recs:
            md = load_metadata(it["identifier"]).get("metadata", {})
            st = sourcetype.detect(
                it["identifier"], md.get("source") or it.get("source"),
                md.get("lineage"), it.get("title"))
            source_types.add(st)
            reviews = int(it.get("num_reviews") or 0)
            downloads = int(it.get("downloads") or 0)
            rating = it.get("avg_rating")
            score = quality_score(st, rating, reviews, downloads)
            if md.get("setlist"):
                arch_setlist_texts.append(md["setlist"])
            row = {
                "identifier": it["identifier"], "show_id": show_id,
                "title": it.get("title"), "source_type": st,
                # Size budget: the app renders source badges (not raw text) and
                # gets lineage from the live detail call — keep only a stub of
                # source_text for the isSoundboard fallback sniff.
                "source_text": (md.get("source") or it.get("source") or "")[:120] or None,
                "lineage": None,
                "taper": md.get("taper"),
                "avg_rating": rating, "num_reviews": reviews,
                "downloads": downloads, "quality_score": score,
            }
            rec_rows.append(row)
            show_recs.append(row)
            if best is None or score > best["quality_score"]:
                best = row

        total_reviews = sum(r["num_reviews"] for r in show_recs)
        rated = [(r["avg_rating"], r["num_reviews"]) for r in show_recs
                 if r["avg_rating"] and r["num_reviews"]]
        avg_rating = (sum(a * n for a, n in rated) / sum(n for _, n in rated)) if rated else None

        # --- setlist ------------------------------------------------------
        sl = setlists.get(show_id) or (setlists.get(date) if show_id == date else None)
        entries: list[dict] = []
        if sl:
            status = "full"
            setlist_full += 1
            labels = set_labels(sl["blocks"])
            pos = 0
            for label, block in zip(labels, sl["blocks"]):
                for title, segue in block:
                    key = songcanon.canonical_key(title)
                    if not key:
                        continue
                    entries.append({
                        "show_id": show_id, "position": pos, "set_label": label,
                        "song_key": key, "song_title": songcanon.canonical_title(title),
                        "segues_into_next": int(segue),
                    })
                    pos += 1
            if arch_setlist_texts:
                recover_segues(entries, parse_archive_setlist(arch_setlist_texts[0]))
            venue, city, state = sl.get("venue"), sl.get("city"), sl.get("state")
        elif arch_setlist_texts:
            status = "partial"
            setlist_partial += 1
            seq = parse_archive_setlist(arch_setlist_texts[0])
            for pos, (title, segue) in enumerate(seq):
                key = songcanon.canonical_key(title)
                if not key:
                    continue
                entries.append({
                    "show_id": show_id, "position": pos, "set_label": "Set 1",
                    "song_key": key, "song_title": songcanon.canonical_title(title),
                    "segues_into_next": int(segue),
                })
            venue = city = state = None
        else:
            status = "none"
            entries = []
            venue = city = state = None

        if city:
            city = PLACE_FIXES.get(city, city)
        if not venue:
            venues = Counter((r.get("venue") or "").strip() for r in recs if r.get("venue"))
            venue = venues.most_common(1)[0][0] if venues else None
            coverages = Counter((r.get("coverage") or "").strip() for r in recs if r.get("coverage"))
            cov = coverages.most_common(1)[0][0] if coverages else None
            if cov and "," in cov:
                city, state = [p.strip() for p in cov.rsplit(",", 1)]
            elif cov:
                city = cov

        entry_rows.extend(entries)
        for e in entries:
            if songcanon.is_non_song(e["song_key"]):
                continue
            agg = song_agg.setdefault(e["song_key"], {
                "title": e["song_title"], "times_played": 0,
                "first_played": date, "last_played": date})
            agg["times_played"] += 1
            agg["first_played"] = min(agg["first_played"], date)
            agg["last_played"] = max(agg["last_played"], date)

        show_rows.append({
            "show_id": show_id, "date": date, "year": year, "month": month, "day": day,
            "era_id": era_for(year), "venue": venue, "city": city, "state": state,
            "setlist_status": status, "recording_count": len(recs),
            "best_identifier": best["identifier"] if best else None,
            "best_source_type": best["source_type"] if best else None,
            "avg_rating": round(avg_rating, 2) if avg_rating else None,
            "total_reviews": total_reviews,
            "total_downloads": show_downloads[show_id],
            "cover_image_url": (gallery.get(date) or [{}])[0].get("url")
                               or legacy_covers.get(date) or None,
        })
        # Early/late rows share a night's scans: one set of rows per date.
        if date not in image_dates:
            image_dates.add(date)
            for position, scan in enumerate(gallery.get(date) or []):
                image_rows.append((date, position, scan["kind"], scan["url"],
                                   scan.get("width"), scan.get("height")))
        fts_inputs.append(fts.build_blob(
            year=year, month=month, day=day, venue=venue, city=city, state=state,
            era_id=era_for(year),
            song_titles=[e["song_title"] for e in entries],
            source_types=source_types, avg_rating=avg_rating,
            total_reviews=total_reviews,
            downloads_percentile=dl_percentile(show_downloads[show_id])))

    # --- digests ----------------------------------------------------------
    digest_rows = []
    digest_dir = CACHE / "digests"
    for row in show_rows:
        p = digest_dir / f"{row['show_id']}.json"
        if p.exists():
            d = read_json(p)
            digest_rows.append((
                row["show_id"], d["consensus_summary"],
                json.dumps(d.get("standout_songs", [])), d.get("sentiment", "mixed"),
                float(d["derived_rating"]), d.get("rating_rationale", ""),
                d.get("model", "unknown"), d.get("generated_at", "")))

    # --- write ------------------------------------------------------------
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.unlink(missing_ok=True)
    db = sqlite3.connect(out_path)
    db.executescript(SCHEMA)
    db.executemany(
        "INSERT INTO shows VALUES(:show_id,:date,:year,:month,:day,:era_id,:venue,:city,:state,"
        ":setlist_status,:recording_count,:best_identifier,:best_source_type,:avg_rating,"
        ":total_reviews,:total_downloads,:cover_image_url)", show_rows)
    db.executemany("INSERT INTO show_images VALUES(?,?,?,?,?,?)", image_rows)
    db.executemany(
        "INSERT INTO recordings VALUES(:identifier,:show_id,:title,:source_type,:source_text,"
        ":lineage,:taper,:avg_rating,:num_reviews,:downloads,:quality_score)", rec_rows)
    track_rows = track_rows_for(r["identifier"] for r in rec_rows)
    db.executemany("INSERT INTO recording_tracks VALUES(?,?)", track_rows)
    db.executemany(
        "INSERT INTO setlist_entries VALUES(:show_id,:position,:set_label,:song_key,"
        ":song_title,:segues_into_next)", entry_rows)
    db.executemany(
        "INSERT INTO songs VALUES(?,?,?,?,?)",
        [(k, v["title"], v["times_played"], v["first_played"], v["last_played"])
         for k, v in sorted(song_agg.items())])
    db.executemany("INSERT INTO ai_digest VALUES(?,?,?,?,?,?,?,?)", digest_rows)
    db.executemany("INSERT INTO song_aliases VALUES(?,?)", songcanon.alias_rows())
    # FTS rowids must equal shows rowids (contentless table, joined by rowid)
    for row, blob in zip(show_rows, fts_inputs):
        rowid = db.execute("SELECT rowid FROM shows WHERE show_id=?", (row["show_id"],)).fetchone()[0]
        db.execute("INSERT INTO show_fts(rowid, blob) VALUES(?,?)", (rowid, blob))

    try:
        git_commit = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True,
            cwd=Path(__file__).parent).stdout.strip()
    except OSError:
        git_commit = "unknown"
    meta = {
        "schema_version": str(SCHEMA_VERSION),
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "git_commit": git_commit,
        "show_count": str(len(show_rows)),
        "recording_count": str(len(rec_rows)),
        "tapes_with_tracks": str(len(track_rows)),
        "best_tapes_with_tracks": str(sum(1 for r in show_rows
                                          if r["best_identifier"] in {i for i, _ in track_rows})),
        "setlist_full": str(setlist_full),
        "setlist_partial": str(setlist_partial),
        "digest_count": str(len(digest_rows)),
        "image_count": str(len(image_rows)),
        "shows_with_images": str(len({r[0] for r in image_rows})),
    }
    db.executemany("INSERT INTO catalog_meta VALUES(?,?)", meta.items())
    db.commit()
    db.execute("ANALYZE")
    db.execute("VACUUM")
    db.close()

    size_mb = out_path.stat().st_size / 1e6
    report = dict(meta, size_mb=f"{size_mb:.1f}", build_seconds=f"{time.time() - t0:.0f}")
    print(json.dumps(report, indent=2))

    if gates:
        errors = []
        if len(show_rows) < 2000:
            errors.append(f"show count {len(show_rows)} < 2000")
        if len(rec_rows) < 15000:
            errors.append(f"recording count {len(rec_rows)} < 15000")
        post72 = [r for r in show_rows if r["year"] >= 1972]
        full72 = [r for r in post72 if r["setlist_status"] == "full"]
        if post72 and len(full72) / len(post72) < 0.85:
            errors.append(f"setlist coverage 1972+ is {len(full72)}/{len(post72)} < 85%")
        if len(image_rows) < 2000:
            errors.append(f"image count {len(image_rows)} < 2000 (gallery.json missing?)")
        if size_mb > 24:
            errors.append(f"size {size_mb:.1f}MB > 24MB budget")
        # Stage 2b fetches best tapes first, so a partial crawl must still
        # cover (nearly) every show's best tape — that's what the home shelf
        # and CarPlay resolve runs against with no network.
        with_tracks = {ident for ident, _ in track_rows}
        best_ids = [r["best_identifier"] for r in show_rows if r["best_identifier"]]
        covered = sum(1 for b in best_ids if b in with_tracks)
        if best_ids and covered / len(best_ids) < 0.9:
            errors.append(f"best-tape track coverage {covered}/{len(best_ids)} < 90% (run `make tracks`)")
        if errors:
            print("BUILD GATES FAILED:\n  " + "\n  ".join(errors), file=sys.stderr)
            sys.exit(1)
        print("build gates passed")


def main() -> None:
    args = sys.argv[1:]
    out_path = OUT / "catalog.sqlite"
    fixture_dates = None
    gates = "--no-gates" not in args
    if "--out" in args:
        out_path = Path(args[args.index("--out") + 1])
    if "--fixture" in args:
        fixture_dates = set(args[args.index("--fixture") + 1].split(","))
        gates = False
    build(out_path, fixture_dates, gates)


if __name__ == "__main__":
    main()
