import Foundation
import Testing
@testable import ShakedownAI

/// Anchor class for locating the test bundle's fixture resources.
final class FixtureAnchor {}

nonisolated func fixtureData(_ name: String) throws -> Data {
    let bundle = Bundle(for: FixtureAnchor.self)
    guard let url = bundle.url(forResource: name, withExtension: "json") else {
        throw NSError(domain: "fixtures", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(name).json"])
    }
    return try Data(contentsOf: url)
}

struct IADecodingTests {

    @Test func decodesRealSearchResponse() throws {
        let data = try fixtureData("search_cornell")
        let decoded = try JSONDecoder().decode(IASearchResponse.self, from: data)
        #expect(decoded.response.numFound > 10)
        #expect(!decoded.response.docs.isEmpty)

        let shows = decoded.response.docs.compactMap(ArchiveAPIClient.show(from:))
        #expect(shows.count == decoded.response.docs.count)
        // Every Cornell doc shares the date; venue and coverage survive flexible decoding.
        #expect(shows.allSatisfy { $0.dateString == "1977-05-08" })
        #expect(shows.contains { $0.venue?.contains("Barton") == true || $0.title.contains("Barton") })
        // Ratings arrive as numbers or strings depending on the doc; parsed ones are in range.
        for rating in shows.compactMap(\.avgRating) {
            #expect(rating >= 0 && rating <= 5)
        }
    }

    @Test func decodesRealMetadataResponse() throws {
        let data = try fixtureData("metadata_cornell")
        let decoded = try JSONDecoder().decode(IAMetadataResponse.self, from: data)
        let detail = ArchiveAPIClient.detail(identifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", from: decoded)

        #expect(detail.tracks.count == 20)
        #expect(detail.venue == "Barton Hall, Cornell University")
        #expect(detail.dateString == "1977-05-08")
        #expect(detail.reviews.count > 100)

        // Tracks are sorted by number and durations parse from "mm:ss".
        let first = try #require(detail.tracks.first)
        #expect(first.trackNumber == 1)
        #expect(first.title.contains("Minglewood"))
        #expect(first.durationSeconds == 381)   // "06:21"
        let numbers = detail.tracks.compactMap(\.trackNumber)
        #expect(numbers == numbers.sorted())
    }

    @Test func flexibleFieldsAbsorbStringsAndArrays() throws {
        let json = """
        {"response": {"numFound": 2, "docs": [
            {"identifier": "a", "venue": ["Winterland", "Arena"], "avg_rating": "4.5",
             "downloads": "1200", "date": "1977-05-08T00:00:00Z", "source": ["sbd reel"]},
            {"identifier": "b", "venue": "Fillmore", "avg_rating": 4.9, "num_reviews": 12,
             "date": "1970-02-13"}
        ]}}
        """
        let decoded = try JSONDecoder().decode(IASearchResponse.self, from: Data(json.utf8))
        let a = decoded.response.docs[0]
        #expect(a.venue == "Winterland")
        #expect(a.avgRating == 4.5)
        #expect(a.downloads == 1200)
        #expect(a.source == "sbd reel")
        let b = decoded.response.docs[1]
        #expect(b.venue == "Fillmore")
        #expect(b.avgRating == 4.9)
    }

    @Test func rejectsPlaceholderDates() {
        #expect(IADates.parse("1970-00-00") == nil)
        #expect(IADates.parse("1977-05-08") != nil)
        #expect(IADates.parse("1977-05-08T00:00:00Z") != nil)
        #expect(IADates.normalizedDayString("1977-05-08T00:00:00Z") == "1977-05-08")
        #expect(IADates.normalizedDayString("1970-00-00") == nil)
    }

    @Test func parsesBothDurationFormats() throws {
        let json = """
        {"files": [
            {"name": "t1.mp3", "format": "VBR MP3", "title": "Loser", "track": "01", "length": "08:52"},
            {"name": "t2.mp3", "format": "VBR MP3", "title": "El Paso", "track": "2/20", "length": "318.42"},
            {"name": "t3.mp3", "format": "Flac", "title": "Skipped", "track": "3", "length": "100"}
        ], "metadata": {"title": "x", "notes": ["line one", "line two"]}}
        """
        let decoded = try JSONDecoder().decode(IAMetadataResponse.self, from: Data(json.utf8))
        let detail = ArchiveAPIClient.detail(identifier: "test", from: decoded)
        #expect(detail.tracks.count == 2)   // FLAC filtered out
        #expect(detail.tracks[0].durationSeconds == 532)
        #expect(detail.tracks[1].durationSeconds == 318.42)
        #expect(detail.tracks[1].trackNumber == 2)
        #expect(detail.notes == "line one\nline two")
    }

    @Test func fallsBackToLowerBitrateMP3WhenNoVBR() throws {
        let json = """
        {"files": [
            {"name": "t1.mp3", "format": "64Kbps MP3", "title": "Loser", "track": "1", "length": "100"},
            {"name": "t2.mp3", "format": "64Kbps MP3", "title": "El Paso", "track": "2", "length": "100"},
            {"name": "t1.flac", "format": "Flac", "title": "Loser", "track": "1", "length": "100"}
        ], "metadata": {"title": "x"}}
        """
        let decoded = try JSONDecoder().decode(IAMetadataResponse.self, from: Data(json.utf8))
        let detail = ArchiveAPIClient.detail(identifier: "test", from: decoded)
        #expect(detail.tracks.count == 2)
        #expect(detail.tracks.map(\.fileName) == ["t1.mp3", "t2.mp3"])
    }

    @Test func prefersVBROverLowerBitratesWithoutDuplicates() throws {
        let json = """
        {"files": [
            {"name": "t1-vbr.mp3", "format": "VBR MP3", "title": "Loser", "track": "1", "length": "100"},
            {"name": "t1-64.mp3", "format": "64Kbps MP3", "title": "Loser", "track": "1", "length": "100"},
            {"name": "t1-128.mp3", "format": "128Kbps MP3", "title": "Loser", "track": "1", "length": "100"}
        ], "metadata": {"title": "x"}}
        """
        let decoded = try JSONDecoder().decode(IAMetadataResponse.self, from: Data(json.utf8))
        let detail = ArchiveAPIClient.detail(identifier: "test", from: decoded)
        #expect(detail.tracks.count == 1)
        #expect(detail.tracks.first?.fileName == "t1-vbr.mp3")
    }

    @Test func streamURLEncodesAwkwardFileNames() throws {
        let url = try #require(ArchiveAPIClient.streamURL(
            identifier: "gd1977-05-08.test",
            fileName: "gd77 d1t01 Scarlet #Begonias.mp3"
        ))
        #expect(url.absoluteString.contains("Scarlet%20%23Begonias.mp3"))
        #expect(url.scheme == "https")
    }

    @Test func normalizesSongKeys() {
        #expect(Track.normalizeSongKey("Scarlet Begonias ->") == "scarlet begonias")
        #expect(Track.normalizeSongKey("Fire On The Mountain") == "fire on the mountain")
        #expect(Track.normalizeSongKey("Playin' In The Band (2)") == "playin' in the band")
    }
}

struct RecordingScoringTests {

    private func makeShow(id: String, rating: Double?, downloads: Int, source: String? = nil) -> Show {
        Show(identifier: id, title: id, date: nil, dateString: "1977-05-08",
             venue: nil, location: nil, year: 1977,
             avgRating: rating, numReviews: 10, downloads: downloads, source: source)
    }

    @Test func soundboardBeatsAudienceAtEqualRating() {
        let sbd = makeShow(id: "gd77.sbd.x", rating: 4.5, downloads: 1000)
        let aud = makeShow(id: "gd77.aud.x", rating: 4.5, downloads: 1000)
        #expect(RecordingRanker.score(sbd) > RecordingRanker.score(aud))
        #expect(RecordingRanker.rank([aud, sbd]).first?.identifier == sbd.identifier)
    }

    @Test func millerTransferGetsBonus() {
        let miller = makeShow(id: "gd72.sbd.miller.1", rating: 4.5, downloads: 1000)
        let plain = makeShow(id: "gd72.sbd.other.1", rating: 4.5, downloads: 1000)
        #expect(RecordingRanker.score(miller) > RecordingRanker.score(plain))
    }

    @Test func missingRatingIsNeutralNotFatal() {
        let unrated = makeShow(id: "gd77.sbd.a", rating: nil, downloads: 1000)
        let low = makeShow(id: "gd77.sbd.b", rating: 1.0, downloads: 1000)
        #expect(RecordingRanker.score(unrated) > RecordingRanker.score(low))
    }

    @Test func tieBreakIsStable() {
        let a = makeShow(id: "aaa", rating: 4.0, downloads: 500)
        let b = makeShow(id: "bbb", rating: 4.0, downloads: 500)
        #expect(RecordingRanker.rank([b, a]).map(\.identifier) == ["aaa", "bbb"])
        #expect(RecordingRanker.rank([a, b]).map(\.identifier) == ["aaa", "bbb"])
    }
}

struct LuceneEscapingTests {

    @Test func escapesLuceneSpecialCharacters() {
        #expect(ArchiveAPIClient.luceneEscaped("Winterland (SF)") == #"Winterland \(SF\)"#)
        #expect(ArchiveAPIClient.luceneEscaped(#"5/8/77: "Cornell""#) == #"5\/8\/77\: \"Cornell\""#)
        #expect(ArchiveAPIClient.luceneEscaped("AND && OR ||") == #"AND \&\& OR \|\|"#)
        #expect(ArchiveAPIClient.luceneEscaped("plain barton hall") == "plain barton hall")
    }

    @Test func venueAndFreeTextAreEscapedInBuiltQuery() {
        let filters = SearchFilters(
            venueText: "barton) OR collection:(etree",
            freeText: "scarlet: fire"
        )
        let query = ArchiveAPIClient.searchQuery(filters: filters)
        #expect(query.contains(#"barton\) OR collection\:\(etree"#))
        #expect(query.contains(#"(scarlet\: fire)"#))
        // The hostile close-paren never appears unescaped.
        #expect(!query.contains("barton)"))
    }

    @Test func numericClausesStayUnescaped() {
        let filters = SearchFilters(yearRange: 1972...1974, minRating: 4.0)
        let query = ArchiveAPIClient.searchQuery(filters: filters)
        #expect(query.contains("year:[1972 TO 1974]"))
        #expect(query.contains("avg_rating:[4.0 TO 5]"))
    }
}

/// Deterministic HTTP stub for provider-level tests: fails everything, or
/// succeeds only for the URL containing a marker string.
nonisolated final class ScriptedHTTPClient: HTTPClient {
    enum Mode: Sendable {
        case alwaysFail
        case succeedWhenURLContains(String)
    }
    private let mode: Mode

    init(mode: Mode) { self.mode = mode }

    func get(_ url: URL) async throws -> Data {
        switch mode {
        case .alwaysFail:
            throw HTTPError.serviceUnavailable
        case .succeedWhenURLContains(let marker):
            guard url.absoluteString.contains(marker) else { throw HTTPError.serviceUnavailable }
            let json = """
            {"response": {"numFound": 1, "docs": [
                {"identifier": "gd1968-05-08.sbd.test", "title": "GD 1968-05-08", "date": "1968-05-08"}
            ]}}
            """
            return Data(json.utf8)
        }
    }
}

struct OnThisDayCachingTests {

    @Test func failedSweepIsNotCached() async {
        // Keep the container alive — CacheStore only holds its mainContext.
        let container = ModelContainerFactory.make(inMemory: true)
        let store = CacheStore(container: container)
        let provider = ArchiveShowProvider(
            client: ArchiveAPIClient(http: ScriptedHTTPClient(mode: .alwaysFail)),
            cache: store
        )
        await #expect(throws: (any Error).self) {
            try await provider.onThisDay(monthDay: "05-08")
        }
        #expect(store.cachedSearch(key: "otd:05-08", maxAge: 3600) == nil)
    }

    @Test func partialSuccessIsCached() async throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let store = CacheStore(container: container)
        let provider = ArchiveShowProvider(
            client: ArchiveAPIClient(http: ScriptedHTTPClient(mode: .succeedWhenURLContains("1965"))),
            cache: store
        )
        let shows = try await provider.onThisDay(monthDay: "05-08")
        #expect(shows.count == 1)
        #expect(store.cachedSearch(key: "otd:05-08", maxAge: 3600)?.count == 1)
    }
}

struct CacheStoreTests {

    @Test @MainActor func roundTripsSearchAndDetail() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let store = CacheStore(container: container)

        store.storeSearch(key: "k1", shows: MockData.shows)
        store.storeDetail(MockData.cornellDetail)

        let shows = store.cachedSearch(key: "k1", maxAge: 60)
        #expect(shows?.count == MockData.shows.count)

        let detail = store.cachedDetail(identifier: MockData.cornell.identifier, maxAge: 60)
        #expect(detail?.tracks.count == MockData.cornellTracks.count)

        // Expired entries are treated as misses.
        let expired = store.cachedSearch(key: "k1", maxAge: 0)
        #expect(expired == nil)
    }
}
