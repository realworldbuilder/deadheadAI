import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "pipeline"))

import fts  # noqa: E402
import songcanon  # noqa: E402
import sourcetype  # noqa: E402
from stage3_setlists import parse_show_file  # noqa: E402
from stage4_build import parse_archive_setlist, quality_score, recover_segues, set_labels  # noqa: E402
from stage_images import classify, gallery_items, memorabilia, pick_image  # noqa: E402


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


# --- jerrygarcia.com galleries -------------------------------------------

GALLERY_PAGE = """
<div class="photos">
<a class="fancybox-show" rel="show_images" data-link="https://jerrygarcia.com/image/grateful-dead-poster-1990-03-24/" title="" href="https://cdn.jerrygarcia.com/u/19900324.jpeg">
    <img width="360" height="360" src="https://cdn.jerrygarcia.com/u/19900324.jpeg" class="attachment-360x360" />
</a>
<a class="fancybox-show" rel="show_images" data-link="https://jerrygarcia.com/image/nassau-coliseum-1990-03-29/" href="https://cdn.jerrygarcia.com/u/fanphoto.jpeg">
    <img width="360" height="360" src="https://cdn.jerrygarcia.com/u/fanphoto.jpeg" />
</a>
</div>
<div class="tickets">
<a class="fancybox-show" rel="ticket_gallery"  data-link="https://jerrygarcia.com/image/1990-03-29-grateful-dead-backstage-pass/" href="https://cdn.jerrygarcia.com/u/b900329.jpeg"><img width="324" height="216" src="https://cdn.jerrygarcia.com/u/b900329.jpeg" /></a><a href="https://cdn.jerrygarcia.com/u/t900329.jpeg" rel="ticket_gallery" class="fancybox-show" data-link="https://jerrygarcia.com/image/1990-03-29-grateful-dead-ticket/"><img height="157" width="319" src="https://cdn.jerrygarcia.com/u/t900329.jpeg" /></a>
</div>
"""


def test_classify_slugs():
    assert classify("https://jerrygarcia.com/image/1989-07-07-grateful-dead-ticket/") == "ticket"
    assert classify("https://jerrygarcia.com/image/1989-07-07-grateful-dead-backstage-pass/") == "backstage_pass"
    assert classify("https://jerrygarcia.com/image/grateful-dead-poster-1990-03-24/") == "poster"
    # odd Ticket Archive slugs the old "-ticket" suffix test missed
    assert classify("https://jerrygarcia.com/image/9-5-79-stub/") == "ticket"
    assert classify("https://jerrygarcia.com/image/1988-06-28-grateful-deadticket/") == "ticket"
    assert classify("https://jerrygarcia.com/image/ticket1993/") == "ticket"
    assert classify("https://jerrygarcia.com/image/nassau-coliseum-1990-03-29/") == "other"


def test_gallery_items_reads_both_carousels_in_document_order():
    items = gallery_items(GALLERY_PAGE)
    assert [i["rel"] for i in items] == ["show_images", "show_images", "ticket_gallery", "ticket_gallery"]
    # attribute order doesn't matter
    assert items[3]["url"] == "https://cdn.jerrygarcia.com/u/t900329.jpeg"
    assert (items[3]["width"], items[3]["height"]) == (319, 157)


def test_memorabilia_keeps_posters_drops_fan_photos_orders_ticket_first():
    scans = memorabilia(gallery_items(GALLERY_PAGE))
    assert [s["kind"] for s in scans] == ["ticket", "poster", "backstage_pass"]
    assert all("fanphoto" not in s["url"] for s in scans)
    # Ticket Archive keeps its aspect-true dimensions; Photos thumbs are crops
    assert (scans[0]["width"], scans[0]["height"]) == (319, 157)
    assert (scans[1]["width"], scans[1]["height"]) == (None, None)


def test_cover_is_first_memorabilia_entry():
    assert pick_image(GALLERY_PAGE) == memorabilia(gallery_items(GALLERY_PAGE))[0]["url"]
    assert pick_image("<p>no gallery</p>") is None


# --- tracks (mirror of ArchiveAPIClient / IAFile) ------------------------

def test_tracks_prefer_one_mp3_format_and_never_duplicate():
    import tracks
    files = [
        {"name": "a.mp3", "format": "VBR MP3", "title": "Scarlet Begonias", "track": "01", "length": "10:12"},
        {"name": "a64.mp3", "format": "64Kbps MP3", "title": "Scarlet Begonias", "track": "01", "length": "10:12"},
        {"name": "a.flac", "format": "Flac", "title": "Scarlet Begonias", "track": "01", "length": "612"},
    ]
    assert [f["name"] for f in tracks.playable_files(files)] == ["a.mp3"]
    fixed_only = [f for f in files if f["format"] != "VBR MP3"]
    assert [f["name"] for f in tracks.playable_files(fixed_only)] == ["a64.mp3"]
    odd = [{"name": "x.mp3", "format": "Ogg Vorbis"}, {"name": "y.mp3", "format": "Sample MP3"}]
    assert [f["name"] for f in tracks.playable_files(odd)] == ["y.mp3"]


def test_track_durations_titles_and_order_match_the_app():
    import tracks
    assert tracks.duration_seconds("06:21") == 381
    assert tracks.duration_seconds("1:02:03") == 3723
    assert tracks.duration_seconds("318.42") == 318.42
    assert tracks.duration_seconds("") is None and tracks.duration_seconds("abc") is None
    assert tracks.track_number("01") == 1 and tracks.track_number("1/2") == 1 and tracks.track_number("x") is None
    # a bare taper file name has nothing left after the prefix: fall back to the name itself
    assert tracks.title_from_filename("gd77-05-08d2t03.mp3") == "gd77-05-08d2t03.mp3"
    assert tracks.title_from_filename("gd1977-05-08.sbd.d2t03.Scarlet_Begonias.mp3") == "Scarlet Begonias"
    built = tracks.build_tracks([
        {"name": "b.mp3", "format": "VBR MP3", "title": "Fire", "track": "2", "length": "12:00"},
        {"name": "z.mp3", "format": "VBR MP3", "title": "Encore Crowd", "length": "0:30"},
        {"name": "a.mp3", "format": "VBR MP3", "track": "1", "length": "600"},
    ])
    assert [t["title"] for t in built] == ["a", "Fire", "Encore Crowd"]
    assert [t["seconds"] for t in built] == [600, 720, 30]
    assert built[0]["track"] == 1 and built[2]["track"] is None
