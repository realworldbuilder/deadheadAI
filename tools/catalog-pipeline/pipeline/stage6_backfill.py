"""Stage 6: backfill notable_shows.json preferredIdentifier from the catalog.

The 67 curated shows shipped with preferredIdentifier null, so every canon
show needed a live archive round-trip before it could play. Point each at
the catalog's best tape so the canon works offline.
"""
import json
import sqlite3
from pathlib import Path

from util import OUT

KB = Path(__file__).resolve().parents[3] / "ShakedownAI" / "Resources" / "knowledge_base" / "notable_shows.json"


def main() -> None:
    db = sqlite3.connect(OUT / "catalog.sqlite")
    best = dict(db.execute(
        "SELECT date, best_identifier FROM shows WHERE best_identifier IS NOT NULL"))

    doc = json.loads(KB.read_text())
    shows = doc["shows"] if isinstance(doc, dict) and "shows" in doc else doc
    filled = 0
    for show in shows:
        identifier = best.get(show.get("date"))
        if identifier and not show.get("preferredIdentifier"):
            show["preferredIdentifier"] = identifier
            filled += 1
    KB.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
    print(f"stage6: filled {filled}/{len(shows)} preferredIdentifiers")


if __name__ == "__main__":
    main()
