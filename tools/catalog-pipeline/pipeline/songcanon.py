"""Song title canonicalization.

`normalize` mirrors Track.normalizeSongKey in
ShakedownAI/Core/Models/DomainModels.swift exactly — the app matches
setlist entries to track titles through this shared contract:
lowercase → strip segue arrows → keep only [a-z' ] → collapse spaces.

`canonical_key` additionally folds known aliases/misspellings (from
data/song_aliases.json) into one canonical key so "GDTRFB",
"Goin' Down the Road Feelin' Bad" and "Going Down the Road Feeling Bad"
are the same song.
"""
import json
import re
from functools import lru_cache
from pathlib import Path

_ARROWS = ("-->", "->", ">")
_NON_ALPHA = re.compile(r"[^a-z' ]")
_SPACES = re.compile(r"\s+")

NON_SONG_KEYS = {"drums", "space", "tuning", "jam", "crowd", "banter", "intro", "interview"}


def normalize(title: str) -> str:
    t = title.lower()
    for arrow in _ARROWS:
        t = t.replace(arrow, "")
    t = _NON_ALPHA.sub(" ", t)
    t = _SPACES.sub(" ", t)
    return t.strip()


@lru_cache(maxsize=1)
def _aliases() -> dict[str, str]:
    path = Path(__file__).resolve().parent.parent / "data" / "song_aliases.json"
    raw = json.loads(path.read_text())
    table: dict[str, str] = {}
    for canonical, variants in raw.items():
        key = normalize(canonical)
        table[key] = key
        for v in variants:
            table[normalize(v)] = key
    return table


def canonical_key(title: str) -> str:
    key = normalize(title)
    return _aliases().get(key, key)


def alias_rows() -> list[tuple[str, str]]:
    """(variant_key, canonical_key) pairs, identity rows excluded — shipped
    in the catalog so the app can fold taper spellings the same way."""
    return sorted((v, c) for v, c in _aliases().items() if v != c)


def canonical_title(title: str) -> str:
    """Display title: the canonical spelling if aliased, else the input cleaned."""
    key = normalize(title)
    canon = _aliases().get(key)
    if canon is None or canon == key:
        return title.strip()
    # find the canonical spelling whose normalized form is `canon`
    path = Path(__file__).resolve().parent.parent / "data" / "song_aliases.json"
    raw = json.loads(path.read_text())
    for canonical in raw:
        if normalize(canonical) == canon:
            return canonical
    return title.strip()


def is_non_song(key: str) -> bool:
    return key in NON_SONG_KEYS
