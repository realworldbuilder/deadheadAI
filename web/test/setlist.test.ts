import { describe, expect, it } from "vitest";
import { align, normalizeSongKey, rows } from "../src/catalog/setlist";
import { resolveRun } from "../src/catalog/runs";
import type { SetlistEntry } from "../src/catalog/queries";

const entry = (position: number, title: string, set = "Set 1", segues = 0): SetlistEntry =>
  ({ show_id: "x", position, set_label: set, song_key: normalizeSongKey(title), song_title: title, segues_into_next: segues });
const tracks = (...titles: string[]) => titles.map((t, i) => ({ title: t, seconds: 100, fileName: `t${i}.mp3` }));

describe("setlist alignment", () => {
  it("normalizes like the phone", () => {
    expect(normalizeSongKey("Scarlet Begonias -> Fire")).toBe("scarlet begonias fire");
    expect(normalizeSongKey("St. Stephen")).toBe("st stephen");
    expect(normalizeSongKey("Truckin'")).toBe("truckin'");
  });
  it("matches exact and whole-word, scanning forward", () => {
    const e = [entry(0, "Scarlet Begonias", "Set 2", 1), entry(1, "Fire on the Mountain", "Set 2"), entry(2, "Morning Dew", "Set 2")];
    const t = tracks("Tuning", "Scarlet Begonias >", "Fire On The Mountain", "Estimated Prophet");
    expect(align(e, t)).toEqual([1, 2, null]);
  });
  it("a combined file carries two consecutive songs", () => {
    const e = [entry(0, "Scarlet Begonias", "Set 2", 1), entry(1, "Fire on the Mountain", "Set 2")];
    const t = tracks("Scarlet Begonias > Fire on the Mountain", "Estimated Prophet");
    expect(align(e, t)).toEqual([0, 0]);
  });
  it("aliases fold taper spellings", () => {
    const e = [entry(0, "One More Saturday Night", "Encore")];
    const t = tracks("One More Saturday Nite");
    expect(align(e, t, { "one more saturday nite": "one more saturday night" })).toEqual([0]);
  });
});

describe("tape rows", () => {
  it("tracks are the rows, shaped by the setlist", () => {
    const e = [entry(0, "Jack Straw", "Set 1"), entry(1, "Scarlet Begonias", "Set 2", 1), entry(2, "Fire on the Mountain", "Set 2"), entry(3, "Morning Dew", "Set 2")];
    const t = tracks("Tuning", "Jack Straw", "Crowd", "Scarlet Begonias", "Fire on the Mountain");
    const r = rows(e, t);
    expect(r).toEqual([
      { kind: "heading", label: "Set 1" },
      { kind: "track", index: 0, segues: false },
      { kind: "track", index: 1, segues: false },
      { kind: "heading", label: "Set 2" },
      { kind: "track", index: 2, segues: false },
      { kind: "track", index: 3, segues: true },
      { kind: "track", index: 4, segues: false },
      { kind: "missing", entry: e[3] },
    ]);
    const trackRows = r.filter((x) => x.kind === "track").map((x) => (x as { index: number }).index);
    expect(trackRows).toEqual([0, 1, 2, 3, 4]);
  });
  it("no setlist means a plain track list", () => {
    expect(rows([], tracks("a", "b"))).toEqual([{ kind: "track", index: 0, segues: false }, { kind: "track", index: 1, segues: false }]);
  });
});

describe("famous runs on a tape", () => {
  const run = { id: "r", date: "1977-05-08", title: "Scarlet > Fire", songKeys: ["scarlet begonias", "fire on the mountain"], blurb: "", eraID: "hiatus-return", tags: [] };
  it("anchors to the tape", () => {
    expect(resolveRun(run, tracks("Estimated Prophet", "Scarlet Begonias", "Fire on the Mountain", "Morning Dew"))).toEqual({ from: 1, to: 2 });
  });
  it("crosses Drums and Space", () => {
    const r = { ...run, songKeys: ["truckin'", "drums", "the other one"] };
    expect(resolveRun(r, tracks("Truckin'", "Drums", "Space", "The Other One"))).toEqual({ from: 0, to: 3 });
  });
  it("gives up when the tape lacks a song", () => {
    expect(resolveRun(run, tracks("Scarlet Begonias", "Morning Dew"))).toBeNull();
  });
});
