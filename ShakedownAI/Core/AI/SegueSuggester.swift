import Foundation

/// Deterministic playlist-flow brain built on the knowledge base's segue
/// graph — the same offline-AI philosophy as LocalKnowledgeAI. Suggestions
/// only ever name songs the KB knows, and every "add this" is resolved
/// against a real recording before anything touches the playlist.
nonisolated enum SegueSuggester {

    struct NextPick: Hashable, Sendable {
        var songKey: String
        var title: String
        var reason: String
        /// The date of the version worth fetching (famous version, or the run
        /// this pairing is canon from) — the anchor for "Find a version".
        var famousDate: String?
    }

    /// What the band would reach for next: segue partners of the playlist's
    /// tail song first, then partners of earlier songs, skipping anything
    /// already on the list. Ranked: canonized run pairing > partner with a
    /// famous version on record > plain segue partner.
    static func nextPicks(after songKeys: [String], kb: KnowledgeBase, limit: Int = 3) -> [NextPick] {
        guard !songKeys.isEmpty else { return [] }
        let present = Set(songKeys)
        var scored: [(pick: NextPick, score: Int)] = []
        var offered = Set<String>()

        for (distanceFromTail, key) in songKeys.reversed().enumerated() {
            guard let song = kb.song(forKey: key) else { continue }
            let positionWeight = max(0, 4 - distanceFromTail)
            for partnerKey in song.seguePartners {
                guard !present.contains(partnerKey),
                      !offered.contains(partnerKey),
                      let partner = kb.song(forKey: partnerKey) else { continue }
                offered.insert(partnerKey)

                var score = 1 + positionWeight
                var reason = "A classic segue partner for \(song.title)."
                var date: String?

                if let run = canonRun(pairing: key, with: partnerKey, kb: kb) {
                    score += 6
                    reason = "Half of a famous jam — \(run.title)."
                    date = run.date
                } else if let famous = partner.famousVersions.first {
                    score += 3
                    reason = "A classic segue partner for \(song.title) — \(famous.label ?? "essential version") from \(famous.date)."
                    date = famous.date
                }

                scored.append((NextPick(songKey: partner.key, title: partner.title,
                                        reason: reason, famousDate: date), score))
            }
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.pick.songKey < rhs.pick.songKey
            }
            .prefix(limit)
            .map(\.pick)
    }

    /// A greedy reorder over the segue graph. Returns the item keys in their
    /// improved order, or nil when the current order already has as many
    /// true-segue adjacencies as the greedy chain can find.
    static func suggestedOrder(for items: [(key: String, songKey: String)], kb: KnowledgeBase) -> [String]? {
        guard items.count >= 3 else { return nil }
        let currentScore = adjacencyScore(items.map(\.songKey), kb: kb)

        var remaining = items
        var chain: [(key: String, songKey: String)] = [remaining.removeFirst()]
        while !remaining.isEmpty {
            let tail = chain[chain.count - 1].songKey
            if let index = remaining.firstIndex(where: { arePartners(tail, $0.songKey, kb: kb) }) {
                chain.append(remaining.remove(at: index))
            } else {
                chain.append(remaining.removeFirst())
            }
        }

        let newOrder = chain.map(\.key)
        let newScore = adjacencyScore(chain.map(\.songKey), kb: kb)
        guard newScore > currentScore, newOrder != items.map(\.key) else { return nil }
        return newOrder
    }

    // MARK: - Graph helpers

    static func arePartners(_ a: String, _ b: String, kb: KnowledgeBase) -> Bool {
        if let songA = kb.song(forKey: a), songA.seguePartners.contains(b) { return true }
        if let songB = kb.song(forKey: b), songB.seguePartners.contains(a) { return true }
        return false
    }

    private static func adjacencyScore(_ keys: [String], kb: KnowledgeBase) -> Int {
        zip(keys, keys.dropFirst()).count { arePartners($0, $1, kb: kb) }
    }

    /// The famous run (if any) where these two songs appear consecutively.
    private static func canonRun(pairing a: String, with b: String, kb: KnowledgeBase) -> FamousRun? {
        kb.runs.first { run in
            zip(run.songKeys, run.songKeys.dropFirst()).contains {
                ($0 == a && $1 == b) || ($0 == b && $1 == a)
            }
        }
    }
}
