import Foundation

/// Bundled, curated Grateful Dead knowledge: the offline brain.
/// Loaded once from Resources/knowledge_base/*.json.
nonisolated struct KnowledgeBase: Sendable {
    let notableShows: [NotableShow]
    let songs: [SongInfo]
    let eras: [EraInfo]
    let journeys: [Journey]
    let quotes: [BandQuote]

    static let empty = KnowledgeBase(notableShows: [], songs: [], eras: [], journeys: [], quotes: [])

    static func loadFromBundle(_ bundle: Bundle = .main) -> KnowledgeBase {
        func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
            guard let url = bundle.url(forResource: name, withExtension: "json")
                    ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "knowledge_base"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        return KnowledgeBase(
            notableShows: load("notable_shows", as: [NotableShow].self) ?? [],
            songs: load("songs", as: [SongInfo].self) ?? [],
            eras: (load("eras", as: [EraInfo].self) ?? []).sorted { $0.startYear < $1.startYear },
            journeys: load("journeys", as: [Journey].self) ?? [],
            quotes: load("quotes", as: [BandQuote].self) ?? []
        )
    }

    // MARK: - Lookups

    func era(id: String) -> EraInfo? {
        eras.first { $0.id == id }
    }

    func era(forYear year: Int) -> EraInfo? {
        eras.first { ($0.startYear...$0.endYear).contains(year) }
    }

    func song(forKey key: String) -> SongInfo? {
        songs.first { $0.key == key }
    }

    /// Fuzzy: matches "china cat" against titles and keys.
    func song(matching text: String) -> SongInfo? {
        let needle = Track.normalizeSongKey(text)
        guard !needle.isEmpty else { return nil }
        if let exact = songs.first(where: { $0.key == needle }) { return exact }
        return songs.first { $0.key.contains(needle) || needle.contains($0.key) }
    }

    func notableShow(on date: String) -> NotableShow? {
        notableShows.first { $0.date == date }
    }

    func showsOn(monthDay: String) -> [NotableShow] {
        notableShows.filter { $0.monthDay == monthDay }
    }

    func shows(inEra eraID: String) -> [NotableShow] {
        notableShows.filter { $0.eraID == eraID }
    }

    func journey(id: String) -> Journey? {
        journeys.first { $0.id == id }
    }

    // MARK: - Daily picks (deterministic)

    /// Rotates through the canon so every day feels different; leans toward
    /// the listener's stronger eras when a taste snapshot exists.
    func heroShow(dayOfYear: Int, taste: TasteSnapshot) -> NotableShow? {
        guard !notableShows.isEmpty else { return nil }
        let sorted = notableShows.sorted { $0.date < $1.date }
        if let favoriteEra = taste.eraWeights.max(by: { $0.value < $1.value })?.key,
           taste.totalSeconds > 1800 {
            // Alternate: even days from the favorite era, odd days from the full canon.
            let eraShows = sorted.filter { $0.eraID == favoriteEra }
            if dayOfYear.isMultiple(of: 2), !eraShows.isEmpty {
                return eraShows[dayOfYear / 2 % eraShows.count]
            }
        }
        return sorted[dayOfYear % sorted.count]
    }

    func quote(dayOfYear: Int) -> BandQuote? {
        guard !quotes.isEmpty else { return nil }
        return quotes[dayOfYear % quotes.count]
    }

    // MARK: - Relatedness (the knowledge graph, in practice)

    /// Tag/era/song overlap score between two notable shows.
    func affinity(_ a: NotableShow, _ b: NotableShow) -> Int {
        var score = 0
        score += 2 * Set(a.tags).intersection(b.tags).count
        if a.eraID == b.eraID { score += 1 }
        let aSongs = Set(a.standoutSongs.map(Track.normalizeSongKey))
        let bSongs = Set(b.standoutSongs.map(Track.normalizeSongKey))
        score += 2 * aSongs.intersection(bSongs).count
        return score
    }

    func related(to show: NotableShow, limit: Int = 5) -> [NotableShow] {
        var scored: [(show: NotableShow, score: Int)] = []
        for candidate in notableShows where candidate.date != show.date {
            let score = affinity(show, candidate)
            if score > 0 { scored.append((candidate, score)) }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.show.date < rhs.show.date
        }
        return scored.prefix(limit).map(\.show)
    }

    /// Shows that match the listener's taste (top songs + era weights).
    func recommendations(for taste: TasteSnapshot, excluding: Set<String> = [], limit: Int = 6) -> [NotableShow] {
        guard taste.totalSeconds > 0 else {
            let beginners = notableShows.filter { $0.tags.contains("beginner-friendly") }
            return Array(beginners.prefix(limit))
        }
        let topSongs = Set(taste.topSongKeys)
        var scored: [(show: NotableShow, score: Double)] = []
        for show in notableShows where !excluding.contains(show.date) {
            let showSongs = Set(show.standoutSongs.map(Track.normalizeSongKey))
            var score = Double(showSongs.intersection(topSongs).count) * 2.0
            score += taste.eraWeights[show.eraID] ?? 0
            if score > 0 { scored.append((show, score)) }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.show.date < rhs.show.date
        }
        return scored.prefix(limit).map(\.show)
    }

    /// Shows matching mood/intent keywords ("mellow", "primal", "1973"...).
    func shows(matchingTags wanted: Set<String>, limit: Int = 8) -> [NotableShow] {
        var scored: [(show: NotableShow, hits: Int)] = []
        for show in notableShows {
            let hits = Set(show.tags).intersection(wanted).count
            if hits > 0 { scored.append((show, hits)) }
        }
        scored.sort { lhs, rhs in
            if lhs.hits != rhs.hits { return lhs.hits > rhs.hits }
            return lhs.show.date < rhs.show.date
        }
        return scored.prefix(limit).map(\.show)
    }
}
