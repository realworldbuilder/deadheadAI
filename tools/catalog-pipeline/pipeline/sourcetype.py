"""Source-type detection: SBD / MATRIX / FM / AUD / UNKNOWN.

Three passes, most reliable first:
1. Identifier patterns — tapers encode the source in the identifier
   (gd77-05-08.sbd.hicks..., gd1989-07-07.mtx.dusborne..., .aud., .fm.).
2. Lineage/source text analysis. An SBD upgrade only fires when the chain
   actually starts at the board (\"SBD>\", \"MASTER SOUNDBOARD\", ...) — being
   *near* the board (\"SBD patch\" of an audience rig) does not count.
   Priority when both appear: MATRIX > FM > SBD > AUD.
3. Keyword fallback across title + description; microphone brand names
   imply AUD only when nothing better matched.
"""
import re

_ID_PATTERNS = [
    ("MATRIX", re.compile(r"\.(mtx|matrix)\.|ultramatrix|\bmatrix\b", re.I)),
    ("FM", re.compile(r"\.fm\.|\bfm\b(?!\w)|broadcast", re.I)),
    # NOTE: "sbeok" is a SHN-verification marker, not a soundboard signal —
    # it appears in AUD identifiers too, so it must not match here.
    ("SBD", re.compile(r"\.(sbd|soundboard)\.|\bsbd\b", re.I)),
    ("AUD", re.compile(r"\.(aud|audience)\.|\baud\b|\bfob\b", re.I)),
]

_LINEAGE_SBD_START = re.compile(
    r"^\s*(sbd|soundboard|master\s+soundboard|board)\b|^\s*sbd\s*>", re.I
)
_MIC_BRANDS = re.compile(
    r"\b(senn?heiser|akg|neumann|nakamichi|nak\s?\d|beyer|schoeps|sony\s+ecm|shure)\b", re.I
)


def _text_signal(text: str) -> str | None:
    """Priority scan of free text (source/lineage/title)."""
    if re.search(r"\bmatrix\b|ultramatrix|\bmtx\b", text, re.I):
        return "MATRIX"
    if re.search(r"\bfm\b(?!\w)|fm\s+broadcast|radio\s+broadcast|pre-?fm", text, re.I):
        return "FM"
    if _LINEAGE_SBD_START.search(text) or re.search(
        r"\b(soundboard|sbd)\s*(>|master|reel|cassette)", text, re.I
    ):
        return "SBD"
    if re.search(r"\baud(ience)?\b|\bfob\b|on\s?stage\s+mic|stage\s+mic|taped\s+by", text, re.I):
        return "AUD"
    return None


def detect(identifier: str, source: str | None = None, lineage: str | None = None,
           title: str | None = None) -> str:
    for label, pat in _ID_PATTERNS:
        if pat.search(identifier):
            return label

    for text in (source, lineage):
        if text:
            got = _text_signal(text)
            if got:
                return got

    combined = " ".join(t for t in (source, lineage, title) if t)
    if combined:
        got = _text_signal(combined)
        if got:
            return got
        if _MIC_BRANDS.search(combined):
            return "AUD"
    return "UNKNOWN"


# Ranking used by the best-recording sort: lower is better.
TIER = {"SBD": 0, "MATRIX": 1, "FM": 2, "AUD": 3, "UNKNOWN": 4}
