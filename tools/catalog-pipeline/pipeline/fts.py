"""FTS blob expansion for one show.

The FTS index matches by pre-expanding every way a Deadhead writes a
date (5-8-77, 5/8/77, 05-08-1977, may 8 1977, ...) into literal tokens,
rather than by fuzzy matching at query time.
"""

MONTH_NAMES = [
    "", "january", "february", "march", "april", "may", "june", "july",
    "august", "september", "october", "november", "december",
]

ERA_TOKENS = {
    "primal": "primal pigpen",
    "anthem": "anthem pigpen",
    "europe-wall": "europe wall of sound keith",
    "hiatus-return": "hiatus return keith",
    "transition": "transition keith",
    "brent": "brent",
    "vince": "vince",
}


def date_variants(year: int, month: int, day: int) -> list[str]:
    yy = year % 100
    out = [f"{year:04d}-{month:02d}-{day:02d}", str(year), f"{yy:02d}", str(year)[:3]]
    for delim in ("-", "/", "."):
        out.append(f"{month}{delim}{day}{delim}{yy:02d}")
        out.append(f"{month:02d}{delim}{day:02d}{delim}{year}")
        out.append(f"{year}{delim}{month}{delim}{day}")
        out.append(f"{month}{delim}{yy:02d}")
    out.append(f"{MONTH_NAMES[month]} {day} {year}")
    out.append(f"{MONTH_NAMES[month]} {year}")
    return out


def build_blob(*, year: int, month: int, day: int, venue: str | None,
               city: str | None, state: str | None, era_id: str | None,
               song_titles: list[str], source_types: set[str],
               avg_rating: float | None, total_reviews: int,
               downloads_percentile: float) -> str:
    parts: list[str] = date_variants(year, month, day)
    if venue:
        parts.append(venue)
    if city:
        parts.append(city)
    if state:
        parts.append(state)
    if era_id:
        parts.append(ERA_TOKENS.get(era_id, era_id))
    parts.extend(song_titles)
    if "SBD" in source_types:
        parts.append("soundboard sbd")
    if "MATRIX" in source_types:
        parts.append("matrix")
    if "AUD" in source_types:
        parts.append("audience aud")
    if "FM" in source_types:
        parts.append("fm broadcast")
    if (avg_rating or 0) >= 4.5 and total_reviews >= 10:
        parts.append("top-rated")
    if downloads_percentile >= 0.9:
        parts.append("popular")
    return " ".join(parts)
