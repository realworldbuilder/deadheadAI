import Foundation

/// Finds the runs inside a catalog setlist — the stretches where one song
/// flows into the next — without trusting any single signal. The catalog's
/// segue flag links two songs when the source setlist wrote the arrow; the
/// knowledge base's segue graph links the classic pairings (Scarlet > Fire,
/// Help > Slip > Frank, China > Rider) on the many nights whose source never
/// did. Drums and Space are transparent: a run crosses them when the songs
/// on either side belong together, and they never open or close a run.
nonisolated enum RunFinder {

    /// The tape's connective tissue — never a run on its own.
    static let bridgeKeys: Set<String> = ["drums", "space", "jam", "drums space", "space jam", "drum solo", "rhythm devils"]

    /// How many consecutive bridges a run may cross between two songs.
    private static let maxBridges = 2

    /// One run: every setlist entry it spans, bridges included, in stage order.
    struct Chain: Hashable, Sendable {
        var entries: [SetlistEntry]

        var setLabel: String { entries.first?.setLabel ?? "" }
        var songKeys: [String] { entries.map(\.songKey) }
        /// The entries that are actual songs (Drums/Space dropped).
        var songs: [SetlistEntry] { entries.filter { !RunFinder.isBridge($0.songKey) } }
        /// "china cat sunflower > i know you rider" — the run's identity across nights.
        var signature: String { songs.map(\.songKey).joined(separator: " > ") }
        /// "China Cat Sunflower > I Know You Rider", bridges kept so the title
        /// reads the way tapers write it.
        var title: String { entries.map { RunFinder.cleanTitle($0.songTitle) }.joined(separator: " > ") }
    }

    static func isBridge(_ key: String) -> Bool { bridgeKeys.contains(key) }

    /// Words a tape's bridge file can be made of ("Drums 2", "Space Jam",
    /// "Drum Solo pt. 1" — digits are already stripped from keys).
    private static let bridgeWords: Set<String> = ["drums", "drum", "space", "jam", "solo", "rhythm", "devils", "pt", "part"]

    /// Whether a tape track is connective tissue rather than a song.
    static func isBridgeTrack(_ key: String) -> Bool {
        let words = key.split(separator: " ")
        return !words.isEmpty && words.allSatisfy { bridgeWords.contains(String($0)) }
    }

    /// Every run of two or more songs in the setlist, in stage order. Runs
    /// never cross a set boundary.
    static func chains(in entries: [SetlistEntry], kb: KnowledgeBase) -> [Chain] {
        let sorted = entries.sorted { $0.position < $1.position }
        var chains: [Chain] = []
        var current: [SetlistEntry] = []
        var index = 0

        func flush() {
            let trimmed = trimmingBridges(current)
            if trimmed.filter({ !isBridge($0.songKey) }).count >= 2 {
                chains.append(Chain(entries: trimmed))
            }
            current = []
        }

        while index < sorted.count {
            let here = sorted[index]
            if current.isEmpty { current = [here] }
            if let (bridges, next) = successor(of: index, in: sorted, kb: kb) {
                current.append(contentsOf: bridges)
                current.append(sorted[next])
                index = next
            } else {
                flush()
                index += 1
            }
        }
        flush()
        return chains
    }

    /// A playable `FamousRun` for a run the catalog found on one night. The
    /// id is namespaced so it can never collide with the curated canon.
    static func run(from chain: Chain, show: CatalogShow) -> FamousRun {
        FamousRun(
            id: "catalog|\(show.showID)|\(chain.entries.first?.position ?? 0)",
            date: show.date,
            title: chain.title,
            songKeys: chain.songKeys.map(Track.normalizeSongKey),
            blurb: blurb(for: chain, show: show),
            eraID: show.eraID,
            tags: chain.songs.count >= 3 ? ["segue", "marathon"] : ["segue"]
        )
    }

    static func isCatalogRun(_ run: FamousRun) -> Bool { run.id.hasPrefix("catalog|") }

    // MARK: - Linking

    /// The entry `index` flows into (and any bridges crossed to reach it),
    /// or nil when the run ends here.
    private static func successor(of index: Int, in entries: [SetlistEntry],
                                  kb: KnowledgeBase) -> (bridges: [SetlistEntry], next: Int)? {
        let here = entries[index]
        var bridges: [SetlistEntry] = []
        var cursor = index + 1
        var flagged = here.seguesIntoNext
        while cursor < entries.count, entries[cursor].setLabel == here.setLabel {
            let candidate = entries[cursor]
            if flagged || links(here.songKey, candidate.songKey, kb: kb) {
                return (bridges, cursor)
            }
            guard isBridge(candidate.songKey), bridges.count < maxBridges else { return nil }
            bridges.append(candidate)
            flagged = candidate.seguesIntoNext
            cursor += 1
        }
        return nil
    }

    private static func links(_ a: String, _ b: String, kb: KnowledgeBase) -> Bool {
        guard !a.isEmpty, !b.isEmpty, a != b else { return false }
        return SegueSuggester.arePartners(a, b, kb: kb)
    }

    private static func trimmingBridges(_ entries: [SetlistEntry]) -> [SetlistEntry] {
        var slice = entries[...]
        while let first = slice.first, isBridge(first.songKey) { slice = slice.dropFirst() }
        while let last = slice.last, isBridge(last.songKey) { slice = slice.dropLast() }
        return Array(slice)
    }

    // MARK: - Words

    /// Setlist titles carry source markup ("E: Black Muddy River", "Masterpiece*").
    static func cleanTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespaces)
        if title.hasPrefix("E: ") { title.removeFirst(3) }
        while title.hasSuffix("*") { title.removeLast() }
        title = title.trimmingCharacters(in: .whitespaces)
        // Sources write the bridges in lowercase ("drums", "space").
        if title == title.lowercased() {
            title = title.capitalized
        }
        return title
    }

    private static func blurb(for chain: Chain, show: CatalogShow) -> String {
        let count = chain.songs.count
        let songs = count == 2 ? "Two songs" : count == 3 ? "Three songs" : "\(count) songs"
        let place = [show.venue, show.location].compactMap { $0 }.joined(separator: ", ")
        let setName = show.setLabelPhrase(chain.setLabel)
        var text = "\(songs) played as one piece, \(setName)"
        text += place.isEmpty ? "." : " at \(place)."
        if let rating = show.avgRating, show.totalReviews > 0 {
            let stars = String(format: "%.1f", rating)
            text += " A night \(show.totalReviews) listeners rate \(stars)."
        }
        return text
    }
}

nonisolated private extension CatalogShow {
    /// "in the second set", "in the encore", "in set three".
    func setLabelPhrase(_ label: String) -> String {
        let lower = label.lowercased()
        if lower.contains("encore") { return "in the encore" }
        let ordinals = ["1": "first", "2": "second", "3": "third", "4": "fourth"]
        if let digit = lower.split(separator: " ").last.map(String.init), let word = ordinals[digit] {
            return "in the \(word) set"
        }
        return lower.isEmpty ? "that night" : "in \(lower)"
    }
}

/// Decides which runs greet the listener on the home page today: a slice of
/// the curated canon that rotates daily (the favorite era leading once
/// there's real listening to go on), then runs the catalog found on the
/// highest-rated nights, no two alike.
nonisolated enum RunShelfPlanner {

    /// Canon runs for the day, one per night so a two-run night (Cornell)
    /// can't crowd the shelf.
    static func canonPicks(_ runs: [FamousRun], dayOfYear: Int, taste: TasteSnapshot, limit: Int) -> [FamousRun] {
        guard !runs.isEmpty, limit > 0 else { return [] }
        let sorted = runs.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        let offset = ((dayOfYear % sorted.count) + sorted.count) % sorted.count
        var rotated = Array(sorted[offset...] + sorted[..<offset])

        if taste.totalSeconds > 1800,
           let era = taste.eraWeights.max(by: { $0.value < $1.value })?.key,
           let favorite = rotated.firstIndex(where: { $0.eraID == era }) {
            rotated.insert(rotated.remove(at: favorite), at: 0)
        }

        var dates = Set<String>()
        return Array(rotated.filter { dates.insert($0.date).inserted }.prefix(limit))
    }

    struct Candidate: Hashable, Sendable {
        var chain: RunFinder.Chain
        var show: CatalogShow
    }

    /// Catalog runs for the day: longer runs on better-rated nights first,
    /// rotated daily, never two of the same sequence, never a night the
    /// canon already covers.
    static func catalogPicks(_ candidates: [Candidate], excludingDates: Set<String>,
                             dayOfYear: Int, limit: Int) -> [FamousRun] {
        guard !candidates.isEmpty, limit > 0 else { return [] }
        let ranked = candidates
            .filter { !excludingDates.contains($0.show.date) }
            .sorted { lhs, rhs in
                let l = score(lhs), r = score(rhs)
                if l != r { return l > r }
                if lhs.show.date != rhs.show.date { return lhs.show.date < rhs.show.date }
                return (lhs.chain.entries.first?.position ?? 0) < (rhs.chain.entries.first?.position ?? 0)
            }
        // The pool: the best of the ranking with no repeated sequence or
        // night, a few days' worth deep. Today's slice rotates through it so
        // every day is drawn from the top, just not the same top.
        var signatures = Set<String>()
        var dates = Set<String>()
        var pool: [Candidate] = []
        for candidate in ranked where pool.count < limit * poolDepth {
            guard signatures.insert(candidate.chain.signature).inserted,
                  dates.insert(candidate.show.date).inserted else { continue }
            pool.append(candidate)
        }
        guard !pool.isEmpty else { return [] }
        let offset = ((dayOfYear % pool.count) + pool.count) % pool.count
        let rotated = Array(pool[offset...] + pool[..<offset])
        return rotated.prefix(limit).map { RunFinder.run(from: $0.chain, show: $0.show) }
    }

    /// How many days of distinct catalog picks the pool holds.
    private static let poolDepth = 4

    private static func score(_ candidate: Candidate) -> Double {
        Double(candidate.chain.songs.count) * 2 + (candidate.show.avgRating ?? 0)
    }
}

/// A run's running time, the way a listener plans a drive around it.
nonisolated enum RunLength {
    /// Seconds of tape across a resolved run, or nil when the tape carries no
    /// durations at all.
    static func seconds(of tracks: [Track], in range: ClosedRange<Int>) -> Double? {
        guard !tracks.isEmpty, range.lowerBound >= 0, range.upperBound < tracks.count else { return nil }
        let known = tracks[range].compactMap(\.durationSeconds)
        guard !known.isEmpty else { return nil }
        return known.reduce(0, +)
    }

    /// "26 min", "1 hr 12 min", "2 hr". Under a minute rounds up to "1 min".
    static func format(seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(minutes) min" }
        if rest == 0 { return "\(hours) hr" }
        return "\(hours) hr \(rest) min"
    }
}

/// A run pinned to one tape: the show, every track on it, and the slice
/// that is the run.
nonisolated struct ResolvedRun: Hashable, Sendable {
    var run: FamousRun
    var show: Show
    var tracks: [Track]
    var range: ClosedRange<Int>

    var runTracks: [Track] { Array(tracks[range]) }
    var seconds: Double? { RunLength.seconds(of: tracks, in: range) }
    var lengthText: String? { seconds.map(RunLength.format) }
    var entries: [PlayerQueueEntry] { runTracks.map { PlayerQueueEntry(show: show, track: $0) } }
}

extension RunFinder {
    /// Every run that lives on one tape, canon first, then whatever the
    /// catalog setlist and the segue graph find — with no run listed twice
    /// when a catalog chain is the same stretch of tape as a canon run.
    /// Pure: hand it the tape and the night's data, get playable ranges back.
    static func runs(onTape tracks: [Track], show: Show, canon: [FamousRun],
                     night: CatalogShow?, setlist: Setlist?, kb: KnowledgeBase) -> [ResolvedRun] {
        var found: [ResolvedRun] = []
        var ranges = Set<ClosedRange<Int>>()
        for run in canon {
            guard let range = RunResolver.resolve(run, in: tracks), ranges.insert(range).inserted else { continue }
            found.append(ResolvedRun(run: run, show: show, tracks: tracks, range: range))
        }
        if let night, let setlist {
            for chain in chains(in: setlist.sets.flatMap(\.entries), kb: kb) {
                let run = self.run(from: chain, show: night)
                guard let range = RunResolver.resolve(run, in: tracks), ranges.insert(range).inserted else { continue }
                found.append(ResolvedRun(run: run, show: show, tracks: tracks, range: range))
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}

/// What the CarPlay Runs tab shows, as plain rows — built here so the
/// wording can be tested without a CarPlay scene.
nonisolated enum RunRows {
    struct Row: Hashable, Sendable {
        var title: String
        var detail: String
    }

    /// "5/8/77 · Barton Hall (Cornell U) · 26 min"
    static func detail(date: String, venue: String?, lengthText: String?) -> String {
        [LocalKnowledgeAI.prettyDate(date), venue, lengthText].compactMap { $0 }.joined(separator: " · ")
    }

    /// The "On this device" section: a play-everything row, then one row per run.
    static func onDevice(_ runs: [ResolvedRun]) -> [Row] {
        guard !runs.isEmpty else { return [] }
        let total = runs.compactMap(\.seconds).reduce(0, +)
        var summary = "\(runs.count) \(runs.count == 1 ? "jam" : "jams")"
        if total > 0 { summary += " · \(RunLength.format(seconds: total))" }
        return [Row(title: "Play every jam on this device", detail: summary)]
            + runs.map { Row(title: $0.run.title, detail: detail(date: $0.run.date, venue: $0.show.venue, lengthText: $0.lengthText)) }
    }

    /// The "Today's shelf" section: a stitch-everything row, then one row per
    /// pick the archive can reach, its running time joining once known.
    static func shelf(picks: [(run: FamousRun, venue: String?, lengthText: String?)], totalLengthText: String?) -> [Row] {
        guard !picks.isEmpty else { return [] }
        var summary = "\(picks.count) \(picks.count == 1 ? "jam" : "jams")"
        if let totalLengthText { summary += " · \(totalLengthText)" }
        return [Row(title: "Play all of today's jams", detail: summary)]
            + picks.map { Row(title: $0.run.title, detail: detail(date: $0.run.date, venue: $0.venue, lengthText: $0.lengthText)) }
    }
}
