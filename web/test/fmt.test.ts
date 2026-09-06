import { describe, expect, it } from "vitest";
import { longDate, mins, mmss, noteNumber, noteStamp, parseHeadDate, parseNoteRef, prettyDate, setlistLines, showTxt, songSlug } from "../src/fmt";

describe("dates the way heads write them", () => {
  it("prettyDate", () => {
    expect(prettyDate("1977-05-08")).toBe("5/8/77");
    expect(prettyDate("1970-02-13")).toBe("2/13/70");
    expect(prettyDate("2026-09-05")).toBe("9/5/26");
    expect(prettyDate("garbage")).toBe("garbage");
  });
  it("longDate is UTC-stable", () => {
    expect(longDate("1977-05-08")).toBe("Sunday, May 8, 1977");
  });
  it("noteStamp looks like a VT terminal", () => {
    expect(noteStamp("1994-05-08T09:12:00.000Z")).toBe("08-MAY-1994 09:12");
  });
  it("parseHeadDate takes every spelling", () => {
    expect(parseHeadDate("5/8/77")).toBe("1977-05-08");
    expect(parseHeadDate("5-8-77")).toBe("1977-05-08");
    expect(parseHeadDate("1977-05-08")).toBe("1977-05-08");
    expect(parseHeadDate("May 8 1977")).toBe("1977-05-08");
    expect(parseHeadDate("1977")).toBe("1977");
    expect(parseHeadDate("'77")).toBe("1977");
    expect(parseHeadDate("Barton Hall")).toBeNull();
    expect(parseHeadDate("13/40/77")).toBeNull();
  });
});

describe("times and numbers", () => {
  it("mmss", () => {
    expect(mmss(581)).toBe("9:41");
    expect(mmss(3612)).toBe("1:00:12");
    expect(mmss(null)).toBe("--:--");
  });
  it("mins", () => {
    expect(mins(4283)).toBe("71 min");
    expect(mins(10260)).toBe("2 h 51 min");
  });
  it("note numbers", () => {
    expect(noteNumber(45, 352)).toBe("45.352");
    expect(parseNoteRef("45.352")).toEqual({ topic: 45, reply: 352 });
    expect(parseNoteRef("45")).toBeNull();
  });
  it("song slugs match stage7", () => {
    expect(songSlug("dark star")).toBe("dark-star");
    expect(songSlug("truckin'")).toBe("truckin");
  });
});

describe("the typed-in setlist", () => {
  const entries = [
    { set_label: "Set 1", song_title: "Lazy Lightnin'", segues_into_next: 1 },
    { set_label: "Set 1", song_title: "Supplication", segues_into_next: 0 },
    { set_label: "Set 2", song_title: "Scarlet Begonias", segues_into_next: 1 },
    { set_label: "Set 2", song_title: "Fire on the Mountain", segues_into_next: 0 },
    { set_label: "Encore", song_title: "One More Saturday Night", segues_into_next: 0 },
  ];
  it("lines", () => {
    expect(setlistLines(entries)).toEqual([
      "Set 1:", "Lazy Lightnin' >", "Supplication", "",
      "Set 2:", "Scarlet Begonias >", "Fire on the Mountain", "",
      "E:", "One More Saturday Night",
    ]);
  });
  it("showTxt", () => {
    const txt = showTxt({
      show: { show_id: "1977-05-08", date: "1977-05-08", venue: "Barton Hall (Cornell U)", city: "Ithaca", state: "NY", setlist_status: "full" },
      entries,
      best: { identifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", source_type: "SBD", avg_rating: 4.8, num_reviews: 312, taper: "Miller" },
      topicNumber: 45,
      origin: "https://nethead.example",
    });
    expect(txt.startsWith("Grateful Dead\n5/8/77  Barton Hall (Cornell U)  Ithaca, NY\nSunday, May 8, 1977\n\nSet 1:\n")).toBe(true);
    expect(txt).toContain("Scarlet Begonias >\n");
    expect(txt).toContain("Best tape: gd77-05-08.sbd.hicks.4982.sbeok.shnf\n  (SBD, 4.8, 312 reviews, Miller)");
    expect(txt).toContain("RDVAX::GRATEFUL topic 45  ·  https://nethead.example/shows/1977-05-08");
    for (const line of txt.split("\n")) if (!line.startsWith("http") && !line.includes("  ·  ")) expect(line.length).toBeLessThanOrEqual(72);
  });
});

describe("the tape list as text", () => {
  it("lines up columns", async () => {
    const { tapeListTxt } = await import("../src/fmt");
    const txt = tapeListTxt({
      handle: "PHISH::HUSSEY", firstShow: "1977-05-08", origin: "https://nethead.example",
      shelves: [{ name: "Top Shelf", items: [
        { show_date: "1977-05-08", display_name: "5/8/77 Barton Hall (Cornell U)", show_identifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf" },
        { show_date: "1970-02-13", display_name: "2/13/70 Fillmore East", show_identifier: "gd1970-02-13.sbd.miller" },
      ] }],
      mixtapes: [{ name: "Sunday Morning", items: [
        { show_date_string: "1977-05-08", track_title: "Scarlet Begonias", duration_seconds: 581, show_identifier: "gd77-05-08.sbd", file_name: "d2t01.mp3" },
      ] }],
    });
    const lines = txt.split("\n");
    expect(lines[0]).toBe("PHISH::HUSSEY tape list");
    expect(lines[1]).toBe("On the bus since 5/8/77");
    expect(lines[4]).toBe("Top Shelf  (2 tapes)");
    expect(lines[5]!.indexOf("Barton Hall")).toBe(lines[6]!.indexOf("Fillmore East"));
    expect(txt).toContain("Mix tape: Sunday Morning  (1 tune, 10 min)");
    expect(txt).toContain("9:41");
  });
});
