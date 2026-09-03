import Foundation

/// The one whole-word song-key containment rule shared by every matcher:
/// exact key, or the key bounded by spaces inside the track key. "caution"
/// matches "caution do not stop on tracks" and a combined "truckin' caution"
/// file, but "star" never anchors on "dark star".
nonisolated enum SongKeyMatch {
    static func matches(_ trackKey: String, key: String) -> Bool {
        if trackKey == key { return true }
        return (" " + trackKey + " ").contains(" " + key + " ")
    }
}

/// Which parts of a listening guide call out a given track.
nonisolated struct GuideMarks: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let highlight = GuideMarks(rawValue: 1 << 0)
    static let transition = GuideMarks(rawValue: 1 << 1)
    static let listenFor = GuideMarks(rawValue: 1 << 2)
}

/// Grounds a guide's prose bullets ("Impressive guitar work during Half Step
/// > Franklin's Tower") against the tape's tracks so the setlist and track
/// rows can carry a mark. The guide carries no song references — only text —
/// so this is deliberately conservative: a missed mark is cheap, a wrong one
/// misleads.
///
/// Rules:
/// - Each track is known by its own key, its catalog-canonical key, and every
///   alias spelling fans use for it (the reverse of the catalog's alias map).
/// - Multi-word or long keys match by whole-word containment anywhere in the
///   line. Short single words ("fire", "eyes", "dew") only match when they
///   are an entire segment of an arrow chain — "Scarlet > Fire" marks both
///   songs; "the fire in his playing" marks nothing.
/// - Only the text before an explanatory "—" is considered.
nonisolated enum GuideTrackMarks {

    /// Track index → marks, unioned across every bullet category.
    static func marks(for guide: ShowGuide, tracks: [Track],
                      aliases: [String: String]) -> [Int: GuideMarks] {
        guard !tracks.isEmpty else { return [:] }
        let candidates = candidateKeys(for: tracks, aliases: aliases)
        var result: [Int: GuideMarks] = [:]
        func apply(_ lines: [String], _ mark: GuideMarks) {
            for line in lines {
                for index in trackIndices(named: line, candidates: candidates) {
                    result[index, default: []].insert(mark)
                }
            }
        }
        apply(guide.musicalHighlights, .highlight)
        apply(guide.recommendedTracks, .highlight)
        apply(guide.bestTransitions, .transition)
        apply(guide.listenFor, .listenFor)
        return result
    }

    /// Indices of the tracks one prose line names.
    static func trackIndices(named line: String, tracks: [Track],
                             aliases: [String: String]) -> Set<Int> {
        trackIndices(named: line, candidates: candidateKeys(for: tracks, aliases: aliases))
    }

    // MARK: - Internals

    private struct Candidate {
        /// Keys specific enough to match anywhere in a line.
        var anywhere: [String]
        /// Short single words that only count as a whole arrow-chain segment.
        var segmentOnly: [String]
    }

    private static func candidateKeys(for tracks: [Track], aliases: [String: String]) -> [Candidate] {
        var variants: [String: [String]] = [:]
        for (variant, canonical) in aliases {
            variants[canonical, default: []].append(variant)
        }
        return tracks.map { track in
            // A combined file ("Scarlet Begonias > Fire On The Mountain") is
            // known by the whole title and by each song it carries.
            var parts = track.title.split(separator: ">").map { Track.normalizeSongKey(String($0)) }
            parts.append(track.songKey)
            var keys = Set<String>()
            for part in parts where !part.isEmpty {
                let canonical = aliases[part] ?? part
                keys.insert(part)
                keys.insert(canonical)
                keys.formUnion(variants[canonical] ?? [])
            }
            var candidate = Candidate(anywhere: [], segmentOnly: [])
            for key in keys.map(loose) where !key.isEmpty {
                if isShort(key) { candidate.segmentOnly.append(key) } else { candidate.anywhere.append(key) }
            }
            return candidate
        }
    }

    private static func isShort(_ key: String) -> Bool {
        !key.contains(" ") && key.count < 6
    }

    /// Models quote song names ('Estimated Prophet'), and normalization keeps
    /// apostrophes for Truckin' and Franklin's — so compare both sides with
    /// apostrophes dropped altogether.
    private static func loose(_ key: String) -> String {
        key.replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func trackIndices(named line: String, candidates: [Candidate]) -> Set<Int> {
        // The song chain lives before any explanatory dash; normalize AFTER
        // splitting on ">" because normalization strips arrows.
        let head = line.split(separator: "—").first.map(String.init) ?? line
        let whole = loose(Track.normalizeSongKey(head))
        guard !whole.isEmpty else { return [] }
        let segments = Set(head.split(separator: ">")
            .map { loose(Track.normalizeSongKey(String($0))) }
            .filter { !$0.isEmpty })
        var found = Set<Int>()
        for (index, candidate) in candidates.enumerated() {
            if candidate.anywhere.contains(where: { SongKeyMatch.matches(whole, key: $0) })
                || candidate.segmentOnly.contains(where: { segments.contains($0) }) {
                found.insert(index)
            }
        }
        return found
    }
}
