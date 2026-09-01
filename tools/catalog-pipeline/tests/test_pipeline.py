import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "pipeline"))

import fts  # noqa: E402
import songcanon  # noqa: E402
import sourcetype  # noqa: E402
from stage3_setlists import parse_show_file  # noqa: E402
from stage4_build import parse_archive_setlist, quality_score, recover_segues, set_labels  # noqa: E402


# --- songcanon -----------------------------------------------------------

def test_normalize_matches_swift_contract():
    # mirrors Track.normalizeSongKey: arrows stripped, [a-z' ] kept, spaces collapsed
    assert songcanon.normalize("Scarlet Begonias -> Fire") == "scarlet begonias fire"
    assert songcanon.normalize("St. Stephen") == "st stephen"
    assert songcanon.normalize("Truckin'") == "truckin'"
    assert songcanon.normalize("  Dark   Star  ") == "dark star"


def test_aliases_fold_to_canonical():
    a = songcanon.canonical_key("GDTRFB")
    b = songcanon.canonical_key("Going Down the Road Feeling Bad")
    c = songcanon.canonical_key("Goin' Down the Road Feelin' Bad")
    assert a == b == c
    assert songcanon.canonical_key("Sugar Magnolla") == songcanon.canonical_key("Sugar Magnolia")


def test_unknown_title_passes_through():
    assert songcanon.canonical_key("Some Bootleg Jam") == "some bootleg jam"


# --- sourcetype ----------------------------------------------------------

def test_identifier_patterns_win():
    assert sourcetype.detect("gd77-05-08.sbd.hicks.4982.sbeok.shnf") == "SBD"
    assert sourcetype.detect("gd1989-07-07.mtx.dusborne.12345.flac16") == "MATRIX"
    assert sourcetype.detect("gd1983-09-06.aud.walker.7132.sbeok.shnf") == "AUD"
    assert sourcetype.detect("gd73-11-30.fm.deadhead.55.shnf") == "FM"


def test_lineage_sbd_requires_board_origin():
    # chain starts at the board -> SBD
    assert sourcetype.detect("gd77-x", source="SBD> Master Reel> DAT") == "SBD"
    # audience rig near the board is NOT a soundboard
    assert sourcetype.detect("gd77-x", source="Sennheiser 421 mics> Sony D5") == "AUD"


def test_matrix_beats_sbd_in_text():
    assert sourcetype.detect("gd77-x", source="Matrix of SBD and AUD reels") == "MATRIX"


def test_unknown():
    assert sourcetype.detect("gd77-generic", source=None) == "UNKNOWN"


# --- quality score -------------------------------------------------------

def test_source_tier_dominates_rating():
    sbd_bad = quality_score("SBD", 3.0, 2, 100)
    aud_great = quality_score("AUD", 5.0, 200, 100000)
    assert sbd_bad > aud_great


def test_review_gate_within_tier():
    gated = quality_score("SBD", 4.0, 6, 100)
    ungated = quality_score("SBD", 4.9, 2, 100)
    assert gated > ungated


def test_shrunk_rating_orders_within_gate():
    better = quality_score("SBD", 4.8, 100, 100)
    worse = quality_score("SBD", 4.1, 100, 100)
    assert better > worse


# --- CMU parser ----------------------------------------------------------

CORNELL = """Barton Hall (Cornell U), Ithica, NY (5/8/77)

New Minglewood Blues
Loser

Scarlet Begonias
Fire on the Mountain

One More Saturday Night
"""


def test_parse_show_file():
    parsed = parse_show_file(CORNELL)
    assert parsed["date"] == "1977-05-08"
    assert parsed["venue"] == "Barton Hall (Cornell U)"
    assert parsed["city"] == "Ithica"
    assert parsed["state"] == "NY"
    assert parsed["blocks"] == [
        [["New Minglewood Blues", 0], ["Loser", 0]],
        [["Scarlet Begonias", 0], ["Fire on the Mountain", 0]],
        [["One More Saturday Night", 0]],
    ]


NINETIES = """Oakland Coliseum Arena, Oakland, CA (Sunday, 1/24/93)

Jack Straw
Bird Song

Playin' in the Band ->
Crazy Fingers
Sugar Magnolia

Knockin' on Heaven's Door
"""


def test_parse_weekday_header_and_segue_markers():
    parsed = parse_show_file(NINETIES)
    assert parsed["date"] == "1993-01-24"
    assert parsed["venue"] == "Oakland Coliseum Arena"
    assert parsed["blocks"][1][0] == ["Playin' in the Band", 1]
    assert parsed["blocks"][1][1] == ["Crazy Fingers", 0]


def test_set_labels_with_encore():
    assert set_labels([["a", "b", "c"], ["d", "e", "f"], ["g"]]) == ["Set 1", "Set 2", "Encore"]


def test_set_labels_single_set():
    assert set_labels([["a", "b"]]) == ["Set 1"]


def test_set_labels_no_encore_when_last_block_long():
    assert set_labels([["a", "b", "c"], ["d", "e", "f", "g"]]) == ["Set 1", "Set 2"]


# --- archive setlist / segues -------------------------------------------

def test_parse_archive_setlist_segues():
    seq = parse_archive_setlist("Scarlet Begonias > Fire on the Mountain, Estimated Prophet")
    assert seq == [
        ("Scarlet Begonias", True),
        ("Fire on the Mountain", False),
        ("Estimated Prophet", False),
    ]


def test_recover_segues_marks_cmu_entries():
    entries = [
        {"song_key": songcanon.canonical_key("Scarlet Begonias"), "segues_into_next": 0},
        {"song_key": songcanon.canonical_key("Fire on the Mountain"), "segues_into_next": 0},
    ]
    recover_segues(entries, parse_archive_setlist("Scarlet Begonias > Fire on the Mountain"))
    assert entries[0]["segues_into_next"] == 1
    assert entries[1]["segues_into_next"] == 0


# --- fts -----------------------------------------------------------------

def test_date_variants_cover_deadhead_formats():
    v = fts.date_variants(1977, 5, 8)
    for expected in ("5-8-77", "5/8/77", "05-08-1977", "may 8 1977", "1977-05-08", "197"):
        assert expected in v, expected


def test_blob_tags():
    blob = fts.build_blob(
        year=1977, month=5, day=8, venue="Barton Hall", city="Ithaca", state="NY",
        era_id="hiatus-return", song_titles=["Scarlet Begonias"],
        source_types={"SBD", "AUD"}, avg_rating=4.8, total_reviews=500,
        downloads_percentile=0.99)
    assert "soundboard" in blob and "top-rated" in blob and "popular" in blob
    assert "Scarlet Begonias" in blob
