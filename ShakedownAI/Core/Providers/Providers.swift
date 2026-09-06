import Foundation

// Provider protocols are MainActor-isolated (the project default) — they're
// consumed by views and stores. Implementations await into the nonisolated
// networking layer, so no work blocks the main thread.

// MARK: - Protocols

protocol LiveRecordingProvider: AnyObject {
    /// Shows matching parsed natural-language filters.
    func shows(matching filters: SearchFilters) async throws -> [Show]
    /// All recordings of one calendar date ("1977-05-08"), best first.
    func recordings(forDate day: String) async throws -> [Show]
    /// Highly rated shows, optionally within a year range.
    func topRated(yearRange: ClosedRange<Int>?, limit: Int) async throws -> [Show]
    /// Shows played on this month-day ("05-08") across all years.
    func onThisDay(monthDay: String) async throws -> [Show]
}

protocol MetadataProvider: AnyObject {
    func detail(for identifier: String) async throws -> RecordingDetail
}

protocol StreamingProvider: AnyObject {
    func streamURL(identifier: String, track: Track) -> URL?
}

protocol AIProvider: AnyObject {
    var name: String { get }
    func chatReply(messages: [ChatTurn], grounding: GroundingContext) async throws -> AsyncThrowingStream<String, any Error>
    func recommend(query: String?, profile: TasteSnapshot, candidates: [Show]) async throws -> Recommendation
    func showGuide(for detail: RecordingDetail, show: Show?) async throws -> ShowGuide
    func parseSearchIntent(_ text: String) async throws -> SearchFilters
    /// Names and orders one auto-generated shelf. Picks must come from `candidates`.
    func curateCollection(brief: CollectionBrief, candidates: [CollectionCandidate]) async throws -> CuratedCollection
}

/// Who the phone is signed in as: the notesfile's row for an Apple ID. The
/// app never shows the handle; it exists so the same shelves come up on the
/// web. Nothing else — no email, no password.
nonisolated struct NetheadAccount: Sendable, Equatable, Codable {
    var id: String
    var handle: String
    var firstShow: String?
}

protocol AuthProvider: AnyObject {
    var currentAccount: NetheadAccount? { get }
    /// Fetches a fresh nonce from the notesfile and returns the hash to put on
    /// the Apple request. Nil when this build has no notesfile.
    func prepareAppleSignIn() async -> String?
    /// Trades Apple's identity token for the notesfile session.
    func signInWithApple(identityToken: Data, fullName: PersonNameComponents?) async throws -> NetheadAccount
    func signOut() async
    /// Re-checks the session at launch; a dead one signs out.
    func refresh() async
}

nonisolated struct FriendProfile: Sendable, Identifiable, Hashable {
    var id: String
    var name: String
    var avatarSystemImage: String
    var nowListeningTo: String?
    var favoriteEra: String
    var compatibility: Double     // 0...1
}

nonisolated struct SessionChatMessage: Sendable, Identifiable, Hashable {
    var id: UUID
    var sender: String
    var text: String
    var isReaction: Bool
}

protocol SocialProvider: AnyObject {
    func friends() async throws -> [FriendProfile]
    func startListeningSession(showIdentifier: String, showName: String) async throws
    func sessionMessages() -> AsyncStream<SessionChatMessage>
    func send(message: String) async
    func endSession() async
}

// MARK: - Live archive-backed provider

final class ArchiveShowProvider: LiveRecordingProvider, MetadataProvider {
    private let client: ArchiveAPIClient
    private let cache: CacheStore?

    private static let searchTTL: TimeInterval = 7 * 24 * 3600
    private static let detailTTL: TimeInterval = 30 * 24 * 3600

    init(client: ArchiveAPIClient = ArchiveAPIClient(), cache: CacheStore?) {
        self.client = client
        self.cache = cache
    }

    func shows(matching filters: SearchFilters) async throws -> [Show] {
        let payload = (try? JSONEncoder().encode(filters)).map { String(decoding: $0, as: UTF8.self) } ?? "none"
        let key = "filters:\(payload)"
        if let hit = cache?.cachedSearch(key: key, maxAge: Self.searchTTL) { return hit }
        let client = self.client
        let filters = filters
        let shows = try await client.search(filters: filters)
        cache?.storeSearch(key: key, shows: shows)
        return shows
    }

    func recordings(forDate day: String) async throws -> [Show] {
        let key = "date:\(day)"
        if let hit = cache?.cachedSearch(key: key, maxAge: Self.detailTTL) { return hit }
        let client = self.client
        let shows = RecordingRanker.rank(try await client.recordings(forDate: day))
        cache?.storeSearch(key: key, shows: shows)
        return shows
    }

    func topRated(yearRange: ClosedRange<Int>?, limit: Int) async throws -> [Show] {
        var query = "avg_rating:[4.3 TO 5] AND num_reviews:[5 TO 10000]"
        if let yearRange {
            query += " AND year:[\(yearRange.lowerBound) TO \(yearRange.upperBound)]"
        }
        let key = "top:\(query):\(limit)"
        if let hit = cache?.cachedSearch(key: key, maxAge: Self.searchTTL) { return hit }
        let client = self.client
        let shows = try await client.searchShows(query: query, rows: limit, sort: "avg_rating desc")
        cache?.storeSearch(key: key, shows: shows)
        return shows
    }

    func onThisDay(monthDay: String) async throws -> [Show] {
        let key = "otd:\(monthDay)"
        if let hit = cache?.cachedSearch(key: key, maxAge: Self.searchTTL) { return hit }
        // The archive has no month-day query, so sweep the touring years with
        // one range query per decade chunk and filter client-side.
        let client = self.client
        var results: [Show] = []
        var anySucceeded = false
        var lastError: (any Error)?
        for chunk in [(1965, 1974), (1975, 1984), (1985, 1995)] {
            let query = "year:[\(chunk.0) TO \(chunk.1)] AND avg_rating:[3.5 TO 5]"
            do {
                let shows = try await client.searchShows(query: query, rows: 400, sort: "downloads desc")
                anySucceeded = true
                results.append(contentsOf: shows.filter { ($0.dateString ?? "").hasSuffix("-" + monthDay) })
            } catch {
                lastError = error
            }
        }
        // A completely failed sweep must not be cached — it would pin an empty
        // "On This Day" for the full TTL. Partial results are still worth keeping.
        guard anySucceeded else { throw lastError ?? HTTPError.serviceUnavailable }
        // Collapse to one best recording per date.
        var byDate: [String: [Show]] = [:]
        for show in results { byDate[show.dateString ?? "", default: []].append(show) }
        let collapsed = byDate.values.compactMap { RecordingRanker.rank($0).first }
            .sorted { ($0.dateString ?? "") < ($1.dateString ?? "") }
        cache?.storeSearch(key: key, shows: collapsed)
        return collapsed
    }

    func detail(for identifier: String) async throws -> RecordingDetail {
        if let hit = cache?.cachedDetail(identifier: identifier, maxAge: Self.detailTTL) { return hit }
        let client = self.client
        let detail = try await client.recordingDetail(identifier: identifier)
        cache?.storeDetail(detail)
        return detail
    }
}

/// Answers from the bundled catalog when it can, and falls back to the
/// live archive for anything the catalog doesn't know (mood queries, shows
/// uploaded after the catalog was generated, or a missing catalog file).
final class CatalogFirstShowProvider: LiveRecordingProvider {
    private let catalog: any ShowCatalog
    private let fallback: any LiveRecordingProvider

    init(catalog: any ShowCatalog, fallback: any LiveRecordingProvider) {
        self.catalog = catalog
        self.fallback = fallback
    }

    func shows(matching filters: SearchFilters) async throws -> [Show] {
        guard catalog.isAvailable else { return try await fallback.shows(matching: filters) }

        var catalogShows: [CatalogShow] = []
        if let songText = filters.songText, !songText.isEmpty {
            let normalized = Track.normalizeSongKey(songText)
            let key = await catalog.songAliases()[normalized] ?? normalized
            catalogShows = await catalog.performances(ofSong: key)
            if catalogShows.isEmpty {
                catalogShows = await catalog.searchText(songText, limit: 60)
            }
        } else if let monthDay = filters.monthDay {
            catalogShows = await catalog.shows(onMonthDay: monthDay)
        } else if let venueText = filters.venueText, !venueText.isEmpty {
            catalogShows = await catalog.searchText(venueText, limit: 60)
        } else if let yearRange = filters.yearRange {
            catalogShows = await catalog.topRated(yearRange: yearRange, limit: 60)
        }

        if let yearRange = filters.yearRange {
            catalogShows = catalogShows.filter { yearRange.contains($0.year) }
        }
        if let monthDay = filters.monthDay {
            catalogShows = catalogShows.filter {
                String(format: "%02d-%02d", $0.month, $0.day) == monthDay
            }
        }
        if let minRating = filters.minRating {
            catalogShows = catalogShows.filter { ($0.avgRating ?? 0) >= minRating }
        }
        if filters.soundboardOnly == true {
            catalogShows = catalogShows.filter {
                $0.bestSourceType == .soundboard || $0.bestSourceType == .matrix
            }
        }
        if filters.sortByRating == true {
            catalogShows.sort { ($0.avgRating ?? 0) > ($1.avgRating ?? 0) }
        }
        var results = catalogShows.compactMap(\.asShow)

        // Mood/free-text queries are the archive's (and the AI's) domain —
        // merge its extras after the catalog's exact answers.
        let needsNetwork = results.isEmpty || (filters.freeText?.isEmpty == false)
        if needsNetwork, let networkShows = try? await fallback.shows(matching: filters) {
            let seen = Set(results.map(\.identifier))
            results.append(contentsOf: networkShows.filter { !seen.contains($0.identifier) })
        }
        return results
    }

    func recordings(forDate day: String) async throws -> [Show] {
        guard catalog.isAvailable else { return try await fallback.recordings(forDate: day) }
        let nights = await catalog.shows(onDate: day)
        var results: [Show] = []
        for night in nights {
            let recordings = await catalog.recordings(forShow: night.showID)
            results.append(contentsOf: recordings.map { makeShow($0, night: night) })
        }
        guard !results.isEmpty else { return try await fallback.recordings(forDate: day) }
        return results
    }

    func topRated(yearRange: ClosedRange<Int>?, limit: Int) async throws -> [Show] {
        guard catalog.isAvailable else { return try await fallback.topRated(yearRange: yearRange, limit: limit) }
        let shows = await catalog.topRated(yearRange: yearRange, limit: limit).compactMap(\.asShow)
        guard !shows.isEmpty else { return try await fallback.topRated(yearRange: yearRange, limit: limit) }
        return shows
    }

    func onThisDay(monthDay: String) async throws -> [Show] {
        guard catalog.isAvailable else { return try await fallback.onThisDay(monthDay: monthDay) }
        let shows = await catalog.shows(onMonthDay: monthDay).compactMap(\.asShow)
        guard !shows.isEmpty else { return try await fallback.onThisDay(monthDay: monthDay) }
        return shows
    }

    /// A playable Show for one specific tape, carrying the night's venue.
    private func makeShow(_ recording: CatalogRecording, night: CatalogShow) -> Show {
        Show(identifier: recording.identifier,
             title: recording.title ?? "Grateful Dead Live at \(night.venue ?? "?") on \(night.date)",
             date: night.asShow?.date,
             dateString: night.date,
             venue: night.venue,
             location: night.location,
             year: night.year,
             avgRating: recording.avgRating,
             numReviews: recording.numReviews,
             downloads: recording.downloads,
             source: recording.sourceText)
    }
}

final class ArchiveStreamingProvider: StreamingProvider {
    func streamURL(identifier: String, track: Track) -> URL? {
        ArchiveAPIClient.streamURL(identifier: identifier, fileName: track.fileName)
    }
}

/// Plays downloaded audio from disk when it's there, otherwise streams.
final class OfflineFirstStreamingProvider: StreamingProvider {
    private let store: DownloadStore
    private let fallback: any StreamingProvider

    init(store: DownloadStore, fallback: any StreamingProvider) {
        self.store = store
        self.fallback = fallback
    }

    func streamURL(identifier: String, track: Track) -> URL? {
        store.localFileURL(identifier: identifier, fileName: track.fileName)
            ?? fallback.streamURL(identifier: identifier, track: track)
    }
}
