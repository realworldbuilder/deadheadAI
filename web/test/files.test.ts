import { describe, expect, it } from "vitest";
import { buildTracks, durationSeconds, playableFiles, streamUrl, stripLeadingTrackNumber, titleFromFileName } from "../src/archive/files";

describe("which files are the tracks", () => {
  it("prefers VBR, one format only", () => {
    const files = [
      { name: "a.mp3", format: "VBR MP3" }, { name: "a64.mp3", format: "64Kbps MP3" }, { name: "a.flac", format: "Flac" },
    ];
    expect(playableFiles(files).map((f) => f.name)).toEqual(["a.mp3"]);
  });
  it("falls back down the ladder", () => {
    const files = [{ name: "a64.mp3", format: "64Kbps MP3" }, { name: "b128.mp3", format: "128Kbps MP3" }];
    expect(playableFiles(files).map((f) => f.name)).toEqual(["b128.mp3"]);
  });
  it("titles from file names", () => {
    expect(titleFromFileName("gd77-05-08d2t01.mp3")).toBe("gd77-05-08d2t01.mp3");
    expect(titleFromFileName("gd1977-05-08d2t01 Scarlet_Begonias.mp3")).toBe("Scarlet Begonias");
    expect(titleFromFileName("gd77-05-08d2t01.Scarlet Begonias.mp3")).toBe("Scarlet Begonias");
  });
  it("strips leading track numbers but not years", () => {
    expect(stripLeadingTrackNumber("01 Shakedown Street")).toBe("Shakedown Street");
    expect(stripLeadingTrackNumber("1999")).toBe("1999");
  });
  it("durations in both formats", () => {
    expect(durationSeconds("9:41")).toBe(581);
    expect(durationSeconds("1:00:12")).toBe(3612);
    expect(durationSeconds("432.18")).toBe(432.18);
    expect(durationSeconds("x")).toBeNull();
  });
  it("orders numbered tracks first, then by name", () => {
    const t = buildTracks([
      { name: "z.mp3", format: "VBR MP3", track: "02", title: "Two", length: "1:00" },
      { name: "y.mp3", format: "VBR MP3", track: "1", title: "One", length: "60" },
      { name: "b.mp3", format: "VBR MP3" }, { name: "a.mp3", format: "VBR MP3" },
    ]);
    expect(t.map((x) => x.fileName)).toEqual(["y.mp3", "z.mp3", "a.mp3", "b.mp3"]);
    expect(t[0]!.seconds).toBe(60);
  });
  it("encodes awkward file names", () => {
    expect(streamUrl("gd77", "Scarlet #Begonias.mp3")).toBe("https://archive.org/download/gd77/Scarlet%20%23Begonias.mp3");
  });
});
