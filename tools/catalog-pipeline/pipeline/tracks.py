"""Which files on a tape are the tracks, and what they're called — a mirror
of the app's ArchiveAPIClient.playableFiles / titleFromFileName / IAFile so
the catalog's track list is exactly what the live detail call would produce
(RunResolver must see the same titles either way).
"""
import re

MP3_FORMAT_PREFERENCE = ["vbr mp3", "128kbps mp3", "64kbps mp3"]

_FILENAME_PREFIX_RE = re.compile(r"^gd\d{2,4}-\d{2}-\d{2}[a-z0-9.]*(d\d+)?t\d+[. ]?")


def is_mp3ish(f: dict) -> bool:
    """Anything worth caching: the formats we prefer or any *.mp3 the archive calls an MP3."""
    fmt = (f.get("format") or "").lower()
    name = (f.get("name") or "").lower()
    return fmt in MP3_FORMAT_PREFERENCE or ("mp3" in fmt and name.endswith(".mp3"))


def playable_files(files: list[dict]) -> list[dict]:
    """Best available MP3s, one format only so tracks never duplicate."""
    for fmt in MP3_FORMAT_PREFERENCE:
        matches = [f for f in files if (f.get("format") or "").lower() == fmt]
        if matches:
            return matches
    return [f for f in files
            if "mp3" in (f.get("format") or "").lower() and (f.get("name") or "").lower().endswith(".mp3")]


def duration_seconds(length) -> float | None:
    """"mm:ss", "hh:mm:ss", or decimal seconds ("432.18") -> seconds."""
    if length is None:
        return None
    text = str(length).strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        pass
    parts = text.split(":")
    try:
        values = [float(p) for p in parts]
    except ValueError:
        return None
    total = 0.0
    for power, value in enumerate(reversed(values)):
        total += value * (60 ** power)
    return total


def track_number(track) -> int | None:
    """Leading integer of the track field: "01" -> 1, "1/2" -> 1."""
    if track is None:
        return None
    m = re.match(r"\d+", str(track))
    return int(m.group()) if m else None


def title_from_filename(name: str) -> str:
    base = re.sub(r"\.[^./]*$", "", name)
    base = _FILENAME_PREFIX_RE.sub("", base, count=1)
    base = base.replace("_", " ")
    return base or name


def build_tracks(files: list[dict]) -> list[dict]:
    """The tape's tracks in play order: [{name, title, track, seconds}]."""
    tracks = []
    for f in playable_files(files):
        tracks.append({
            "name": f["name"],
            "title": f.get("title") or title_from_filename(f["name"]),
            "track": track_number(f.get("track")),
            "seconds": duration_seconds(f.get("length")),
        })

    def order(t):
        # numbered tracks first, ascending; unnumbered after, by file name
        return (0, t["track"], t["name"]) if t["track"] is not None else (1, 0, t["name"])

    tracks.sort(key=order)
    return tracks
