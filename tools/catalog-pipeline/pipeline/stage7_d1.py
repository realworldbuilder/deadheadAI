"""Stage 7: dump a schema-3 catalog into D1-compatible SQL.

Usage:
    python stage7_d1.py --in PATH --out-dir DIR [--part-bytes N] [--single]

D1 (Cloudflare's SQLite) takes plain SQL but not a `.dump`: no BEGIN/COMMIT,
no PRAGMA, statements under ~100 KB, and `show_fts` is a contentless FTS5
table whose blob can't be read back from the file — it is rebuilt here from
the same `fts.build_blob` stage 4 used. One statement per line so the same
files feed `wrangler d1 execute --file` and D1's `exec()` (which splits on
newlines); newlines inside text are emitted as `||char(10)||`.

Outputs:
    DIR/catalog.tables.NNN.sql   regular tables + derived web_* tables
    DIR/catalog.fts.NNN.sql      show_fts rebuild
    DIR/catalog.manifest.json    parts, row counts, byte sizes, source meta
--single writes catalog.tables.sql / catalog.fts.sql (one part each) — the
shape the web test fixture wants.
"""
import argparse
import bisect
import json
import re
import sqlite3
import sys
import time
from pathlib import Path

import fts

STAGE7_VERSION = 1
MAX_STATEMENT_BYTES = 90_000
DEFAULT_PART_BYTES = 4_000_000

_SLUG_STRIP = re.compile(r"[^a-z0-9 ]")
_SLUG_SPACES = re.compile(r"\s+")


def sql_literal(value) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, (bytes, memoryview)):
        return "X'" + bytes(value).hex() + "'"
    text = str(value).replace("'", "''")
    if "\r" in text:
        text = text.replace("\r", "")
    if "\n" in text:
        pieces = ["'" + p + "'" for p in text.split("\n")]
        return "||char(10)||".join(pieces)
    return "'" + text + "'"


def dump_schema(db: sqlite3.Connection) -> list[str]:
    """DROP + CREATE for every regular table and index, from sqlite_master."""
    out: list[str] = []
    rows = db.execute(
        "SELECT type, name, tbl_name, sql FROM sqlite_master "
        "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'show_fts%' "
        "ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, rowid").fetchall()
    for kind, name, _tbl, sql in rows:
        if kind == "table":
            out.append(f"DROP TABLE IF EXISTS {name};")
        flat = " ".join(line.strip() for line in sql.splitlines())
        out.append(flat + ";")
    return out


def insert_chunks(db: sqlite3.Connection, table: str, max_bytes: int = MAX_STATEMENT_BYTES):
    cols = [r[1] for r in db.execute(f"PRAGMA table_info({table})")]
    col_list = ",".join(cols)
    head = f"INSERT INTO {table}({col_list}) VALUES "
    buf: list[str] = []
    size = len(head)
    for row in db.execute(f"SELECT {col_list} FROM {table} ORDER BY rowid"):
        rendered = "(" + ",".join(sql_literal(v) for v in row) + ")"
        if buf and size + len(rendered) + 2 > max_bytes:
            yield head + ",".join(buf) + ";"
            buf, size = [], len(head)
        buf.append(rendered)
        size += len(rendered) + 1
    if buf:
        yield head + ",".join(buf) + ";"


def fts_rows(db: sqlite3.Connection):
    """(rowid, blob) per show, rebuilt the way stage 4 built them.

    One documented divergence: stage 4 fed the unrounded weighted rating into
    build_blob; the file stores it rounded to 2 dp, so a show sitting at
    4.495–4.499 could gain the `top-rated` tag here. Harmless.
    """
    totals = sorted(r[0] for r in db.execute("SELECT total_downloads FROM shows"))

    def percentile(v: int) -> float:
        return bisect.bisect_left(totals, v) / len(totals) if totals else 0.0

    shows = db.execute(
        "SELECT rowid, show_id, year, month, day, venue, city, state, era_id, "
        "avg_rating, total_reviews, total_downloads FROM shows ORDER BY rowid").fetchall()
    for (rowid, show_id, year, month, day, venue, city, state, era_id,
         avg_rating, total_reviews, total_downloads) in shows:
        titles = [r[0] for r in db.execute(
            "SELECT song_title FROM setlist_entries WHERE show_id=? ORDER BY position", (show_id,))]
        sources = {r[0] for r in db.execute(
            "SELECT DISTINCT source_type FROM recordings WHERE show_id=?", (show_id,))}
        blob = fts.build_blob(
            year=year, month=month, day=day, venue=venue, city=city, state=state,
            era_id=era_id, song_titles=titles, source_types=sources,
            avg_rating=avg_rating, total_reviews=total_reviews,
            downloads_percentile=percentile(total_downloads))
        yield rowid, blob


def fts_statements(rows, max_bytes: int = MAX_STATEMENT_BYTES):
    yield "DROP TABLE IF EXISTS show_fts;"
    yield ("CREATE VIRTUAL TABLE show_fts USING fts5(blob, content='', "
           "tokenize='unicode61 remove_diacritics 2');")
    head = "INSERT INTO show_fts(rowid, blob) VALUES "
    buf: list[str] = []
    size = len(head)
    for rowid, blob in rows:
        rendered = f"({rowid},{sql_literal(blob)})"
        if buf and size + len(rendered) + 2 > max_bytes:
            yield head + ",".join(buf) + ";"
            buf, size = [], len(head)
        buf.append(rendered)
        size += len(rendered) + 1
    if buf:
        yield head + ",".join(buf) + ";"


def slug_for(song_key: str) -> str:
    s = _SLUG_STRIP.sub("", song_key.lower())
    return _SLUG_SPACES.sub("-", s.strip())


def derived_statements(db: sqlite3.Connection, blobs: list[tuple[int, str]], meta: dict):
    """Small tables that keep hot pages to indexed point reads on D1."""
    yield "DROP TABLE IF EXISTS web_year_counts;"
    yield ("CREATE TABLE web_year_counts(year INTEGER PRIMARY KEY, show_count INTEGER NOT NULL, "
           "recording_count INTEGER NOT NULL, first_date TEXT NOT NULL, last_date TEXT NOT NULL);")
    rows = db.execute(
        "SELECT year, COUNT(*), SUM(recording_count), MIN(date), MAX(date) "
        "FROM shows GROUP BY year ORDER BY year").fetchall()
    if rows:
        yield ("INSERT INTO web_year_counts(year,show_count,recording_count,first_date,last_date) VALUES "
               + ",".join("(" + ",".join(sql_literal(v) for v in r) + ")" for r in rows) + ";")

    yield "DROP TABLE IF EXISTS web_song_slugs;"
    yield "CREATE TABLE web_song_slugs(slug TEXT PRIMARY KEY, song_key TEXT NOT NULL);"
    seen: dict[str, str] = {}
    slug_rows: list[tuple[str, str]] = []
    for (key,) in db.execute("SELECT song_key FROM songs ORDER BY song_key"):
        slug = slug_for(key) or "song"
        base, n = slug, 2
        while slug in seen and seen[slug] != key:
            slug = f"{base}-{n}"
            n += 1
        seen[slug] = key
        slug_rows.append((slug, key))
    for i in range(0, len(slug_rows), 400):
        chunk = slug_rows[i:i + 400]
        yield ("INSERT INTO web_song_slugs(slug,song_key) VALUES "
               + ",".join(f"({sql_literal(s)},{sql_literal(k)})" for s, k in chunk) + ";")

    yield "DROP TABLE IF EXISTS web_search_blob;"
    yield "CREATE TABLE web_search_blob(rowid INTEGER PRIMARY KEY, blob TEXT NOT NULL);"
    head = "INSERT INTO web_search_blob(rowid,blob) VALUES "
    buf: list[str] = []
    size = len(head)
    for rowid, blob in blobs:
        rendered = f"({rowid},{sql_literal(blob)})"
        if buf and size + len(rendered) + 2 > MAX_STATEMENT_BYTES:
            yield head + ",".join(buf) + ";"
            buf, size = [], len(head)
        buf.append(rendered)
        size += len(rendered) + 1
    if buf:
        yield head + ",".join(buf) + ";"

    yield "DROP TABLE IF EXISTS web_meta;"
    yield "CREATE TABLE web_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);"
    items = dict(meta)
    items["exported_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    items["stage7_version"] = str(STAGE7_VERSION)
    yield ("INSERT INTO web_meta(key,value) VALUES "
           + ",".join(f"({sql_literal(k)},{sql_literal(v)})" for k, v in items.items()) + ";")


def table_statements(db: sqlite3.Connection, blobs: list[tuple[int, str]], meta: dict):
    yield from dump_schema(db)
    tables = [r[0] for r in db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' "
        "AND name NOT LIKE 'show_fts%' ORDER BY rowid")]
    for table in tables:
        yield from insert_chunks(db, table)
    yield from derived_statements(db, blobs, meta)


def write_parts(statements, out_dir: Path, prefix: str, part_bytes: int, single: bool) -> list[dict]:
    parts: list[dict] = []
    buf: list[str] = []
    size = 0
    count = 0

    def flush():
        nonlocal buf, size
        if not buf:
            return
        name = f"{prefix}.sql" if single else f"{prefix}.{len(parts):03d}.sql"
        path = out_dir / name
        path.write_text("\n".join(buf) + "\n", encoding="utf-8")
        parts.append({"file": name, "statements": len(buf), "bytes": path.stat().st_size})
        buf, size = [], 0

    for stmt in statements:
        count += 1
        if not single and buf and size + len(stmt) + 1 > part_bytes:
            flush()
        buf.append(stmt)
        size += len(stmt) + 1
    flush()
    return parts


def dump(src: Path, out_dir: Path, part_bytes: int = DEFAULT_PART_BYTES, single: bool = False) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    for old in out_dir.glob("catalog.*.sql"):
        old.unlink()
    db = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
    try:
        meta = {k: v for k, v in db.execute("SELECT key, value FROM catalog_meta")}
        blobs = list(fts_rows(db))
        table_parts = write_parts(table_statements(db, blobs, meta), out_dir, "catalog.tables",
                                  part_bytes, single)
        fts_parts = write_parts(fts_statements(blobs), out_dir, "catalog.fts", part_bytes, single)
        counts = {t: db.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                  for (t,) in db.execute(
                      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' "
                      "AND name NOT LIKE 'show_fts%'")}
    finally:
        db.close()
    manifest = {
        "source": str(src), "source_meta": meta, "row_counts": counts,
        "fts_rows": len(blobs), "tables": table_parts, "fts": fts_parts,
        "stage7_version": STAGE7_VERSION,
    }
    (out_dir / "catalog.manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--part-bytes", type=int, default=DEFAULT_PART_BYTES)
    ap.add_argument("--single", action="store_true")
    args = ap.parse_args()
    manifest = dump(Path(args.src), Path(args.out_dir), args.part_bytes, args.single)
    total = sum(p["bytes"] for p in manifest["tables"] + manifest["fts"])
    print(f"stage7: {len(manifest['tables'])} table part(s), {len(manifest['fts'])} fts part(s), "
          f"{total / 1e6:.1f} MB, {manifest['fts_rows']} shows", file=sys.stderr)


if __name__ == "__main__":
    main()
