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

nonisolated struct UserAccount: Sendable, Equatable {
    var displayName: String
    var appleUserID: String?
}

protocol AuthProvider: AnyObject {
    var currentAccount: UserAccount? { get }
    func signInLocally(displayName: String) async throws -> UserAccount
    func signInWithApple(userID: String, displayName: String) async throws -> UserAccount
    func signOut() async
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
        for chunk in [(1965, 1974), (1975, 1984), (1985, 1995)] {
            let query = "year:[\(chunk.0) TO \(chunk.1)] AND avg_rating:[3.5 TO 5]"
            let shows = (try? await client.searchShows(query: query, rows: 400, sort: "downloads desc")) ?? []
            results.append(contentsOf: shows.filter { ($0.dateString ?? "").hasSuffix("-" + monthDay) })
        }
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

final class ArchiveStreamingProvider: StreamingProvider {
    func streamURL(identifier: String, track: Track) -> URL? {
        ArchiveAPIClient.streamURL(identifier: identifier, fileName: track.fileName)
    }
}
