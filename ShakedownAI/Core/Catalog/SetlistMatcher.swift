import Foundation

/// Aligns a catalog setlist against the actual tracks of one recording so
/// every setlist song the tape contains is tappable at its track index.
///
/// Monotonic greedy alignment, same matching rules as RunResolver: exact
/// key or whole-word containment (handles combined "Scarlet > Fire" files
/// and split "Playing pt. 2" files), scanning forward only. Non-song
/// tracks (tuning, crowd) are skipped freely; a setlist song the tape
/// doesn't carry gets a nil index and renders dimmed.
nonisolated enum SetlistMatcher {

    struct MatchedEntry: Hashable, Sendable {
        var entry: SetlistEntry
        var trackIndex: Int?
    }

    /// `aliases` folds taper spellings to canonical keys ("one more
    /// saturday nite" → "one more saturday night") — ship it from the
    /// catalog's song_aliases table.
    static func align(_ entries: [SetlistEntry], with tracks: [Track],
                      aliases: [String: String] = [:]) -> [MatchedEntry] {
        let trackKeys = tracks.map { track in
            let key = track.songKey
            return aliases[key] ?? key
        }
        var cursor = 0
        var result: [MatchedEntry] = []
        for entry in entries.sorted(by: { $0.position < $1.position }) {
            let key = entry.songKey
            guard !key.isEmpty else {
                result.append(MatchedEntry(entry: entry, trackIndex: nil))
                continue
            }
            var found: Int?
            // A combined file can carry consecutive setlist songs, so the
            // previous match's track is still a valid landing spot.
            let searchStart = max(0, cursor - 1)
            for index in searchStart..<trackKeys.count where matches(trackKeys[index], key: key) {
                found = index
                break
            }
            if let found {
                result.append(MatchedEntry(entry: entry, trackIndex: found))
                cursor = found + 1
            } else {
                result.append(MatchedEntry(entry: entry, trackIndex: nil))
            }
        }
        return result
    }

    private static func matches(_ trackKey: String, key: String) -> Bool {
        SongKeyMatch.matches(trackKey, key: key)
    }
}
