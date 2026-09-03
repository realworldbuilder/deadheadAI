import Foundation

/// Anchors a curated `FamousRun` to the actual tracks of a specific recording.
/// The AI layer never invents track indices — a run only surfaces when its
/// song sequence is found, in order, on the tape in front of the user.
nonisolated enum RunResolver {

    /// Longest tolerated stretch of unrelated tracks between two songs of a
    /// run (covers "Drums"/"Jam" bridges and two-part transfers).
    private static let maxGap = 1

    /// The contiguous track range covering the run, or nil when this transfer
    /// doesn't contain the songs in order (different splits, missing sets…).
    static func resolve(_ run: FamousRun, in tracks: [Track]) -> ClosedRange<Int>? {
        let keys = run.songKeys.map(Track.normalizeSongKey).filter { !$0.isEmpty }
        guard !keys.isEmpty, !tracks.isEmpty else { return nil }

        // A song can appear more than once on a tape (splits, both sets), so
        // try every plausible anchor for the first key instead of binding
        // greedily to the earliest occurrence.
        for start in tracks.indices where matches(tracks[start].songKey, key: keys[0]) {
            if let range = match(keys, in: tracks, startingAt: start) {
                return range
            }
        }
        return nil
    }

    private static func match(_ keys: [String], in tracks: [Track], startingAt start: Int) -> ClosedRange<Int>? {
        var keyIndex = 0
        var last = start

        // One combined-title track ("Truckin' > Caution" as a single file)
        // may satisfy several consecutive keys.
        while keyIndex < keys.count, matches(tracks[start].songKey, key: keys[keyIndex]) {
            keyIndex += 1
        }

        while keyIndex < keys.count {
            guard last + 1 < tracks.count else { return nil }
            var found: Int?
            let window = (last + 1)...min(last + 1 + maxGap, tracks.count - 1)
            for candidate in window where matches(tracks[candidate].songKey, key: keys[keyIndex]) {
                found = candidate
                break
            }
            guard let next = found else { return nil }
            last = next
            keyIndex += 1
            while keyIndex < keys.count, matches(tracks[next].songKey, key: keys[keyIndex]) {
                keyIndex += 1
            }
        }
        return start...last
    }

    private static func matches(_ trackKey: String, key: String) -> Bool {
        SongKeyMatch.matches(trackKey, key: key)
    }
}

/// Keeps model-written transition lines honest: every song named in a
/// "Song A > Song B — why" line must exist on the tape, or the line is dropped.
/// This is what lets the remote model mine community reviews for celebrated
/// runs without ever inventing a segue the recording doesn't contain.
nonisolated enum TransitionGrounding {
    static func filter(_ lines: [String], tracks: [Track]) -> [String] {
        let trackKeys = tracks.map(\.songKey).filter { !$0.isEmpty }
        guard !trackKeys.isEmpty else { return [] }
        return lines.filter { line in
            // The segue chain lives before any explanatory dash; normalize
            // AFTER splitting on ">" because normalization strips arrows.
            let head = line.split(separator: "—").first.map(String.init) ?? line
            let parts = head.split(separator: ">")
                .map { Track.normalizeSongKey(String($0)) }
                .filter { !$0.isEmpty }
            guard !parts.isEmpty else { return false }
            return parts.allSatisfy { part in
                trackKeys.contains { key in
                    key == part
                        || (" " + key + " ").contains(" " + part + " ")
                        || (" " + part + " ").contains(" " + key + " ")
                }
            }
        }
    }
}
