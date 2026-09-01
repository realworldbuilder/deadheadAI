import Foundation
import Testing
@testable import ShakedownAI

// MARK: - SetlistMatcher (pure, no fixture)

struct SetlistMatcherTests {
    private func entry(_ position: Int, _ title: String, set: String = "Set 1") -> SetlistEntry {
        SetlistEntry(position: position, setLabel: set,
                     songKey: Track.normalizeSongKey(title), songTitle: title,
                     seguesIntoNext: false)
    }

    private func track(_ title: String) -> Track {
        Track(fileName: title.replacingOccurrences(of: " ", with: "") + ".mp3", title: title,
              trackNumber: nil, durationSeconds: 300)
    }

    @Test func alignsInOrder() {
        let entries = [entry(0, "Jack Straw"), entry(1, "Deal"), entry(2, "Bird Song")]
        let tracks = [track("Jack Straw"), track("Deal"), track("Bird Song")]
        let matched = SetlistMatcher.align(entries, with: tracks)
        #expect(matched.map(\.trackIndex) == [0, 1, 2])
    }

    @Test func skipsNonSongTracks() {
        let entries = [entry(0, "Jack Straw"), entry(1, "Deal")]
        let tracks = [track("Tuning"), track("Jack Straw"), track("Crowd"), track("Deal")]
        let matched = SetlistMatcher.align(entries, with: tracks)
        #expect(matched.map(\.trackIndex) == [1, 3])
    }

    @Test func combinedFileSatisfiesConsecutiveSongs() {
        let entries = [entry(0, "Scarlet Begonias"), entry(1, "Fire on the Mountain")]
        let tracks = [track("Scarlet Begonias > Fire on the Mountain")]
        let matched = SetlistMatcher.align(entries, with: tracks)
        #expect(matched.map(\.trackIndex) == [0, 0])
    }

    @Test func missingSongGetsNilWithoutDerailingLaterMatches() {
        let entries = [entry(0, "Jack Straw"), entry(1, "Loser"), entry(2, "Deal")]
        let tracks = [track("Jack Straw"), track("Deal")]
        let matched = SetlistMatcher.align(entries, with: tracks)
        #expect(matched.map(\.trackIndex) == [0, nil, 1])
    }

    @Test func aliasFoldsTaperSpellings() {
        let entries = [entry(0, "One More Saturday Night")]
        let tracks = [track("One More Saturday Nite")]
        let aliases = ["one more saturday nite": "one more saturday night"]
        #expect(SetlistMatcher.align(entries, with: tracks).map(\.trackIndex) == [nil])
        #expect(SetlistMatcher.align(entries, with: tracks, aliases: aliases).map(\.trackIndex) == [0])
    }

    @Test func repeatedSongMatchesForward() {
        // Cornell encore shape: St. Stephen > NFA > St. Stephen
        let entries = [entry(0, "St. Stephen"), entry(1, "Not Fade Away"), entry(2, "St. Stephen")]
        let tracks = [track("St. Stephen"), track("Not Fade Away"), track("St. Stephen")]
        let matched = SetlistMatcher.align(entries, with: tracks)
        #expect(matched.map(\.trackIndex) == [0, 1, 2])
    }

    @Test func setlistGroupsBySetLabelInOrder() {
        let entries = [
            entry(0, "Jack Straw", set: "Set 1"),
            entry(1, "Deal", set: "Set 1"),
            entry(2, "Scarlet Begonias", set: "Set 2"),
            entry(3, "One More Saturday Night", set: "Encore"),
        ]
        let setlist = Setlist(showID: "1977-05-08", status: .full, entries: entries)
        #expect(setlist.sets.map(\.label) == ["Set 1", "Set 2", "Encore"])
        #expect(setlist.sets[0].entries.count == 2)
    }
}

// MARK: - CatalogStore against the built fixture

struct CatalogStoreTests {
    private static func fixtureStore() -> CatalogStore? {
        guard let url = Bundle(for: BundleToken.self)
            .url(forResource: "catalog-fixture", withExtension: "sqlite") else { return nil }
        let store = CatalogStore(fileURL: url)
        return store.isAvailable ? store : nil
    }

    private final class BundleToken {}

    @Test func missingFileDegradesGracefully() async {
        let store = CatalogStore(fileURL: URL(fileURLWithPath: "/nonexistent/catalog.sqlite"))
        #expect(store.isAvailable == false)
        let shows = await store.shows(onDate: "1977-05-08")
        #expect(shows.isEmpty)
    }

    @Test func fixtureOpensWithSaneCounts() async throws {
        let store = try #require(Self.fixtureStore())
        let meta = await store.meta()
        #expect(meta["schema_version"] == "1")
        #expect(Int(meta["show_count"] ?? "0") ?? 0 >= 10)
    }

    @Test func cornellHasRecordingsBestFirst() async throws {
        let store = try #require(Self.fixtureStore())
        let recordings = await store.recordings(forShow: "1977-05-08")
        #expect(!recordings.isEmpty)
        let scores = recordings.map(\.qualityScore)
        #expect(scores == scores.sorted(by: >))
        #expect(recordings.first?.sourceType == .soundboard || recordings.first?.sourceType == .matrix)
    }

    @Test func cornellSetlistIsGroupedIntoSets() async throws {
        let store = try #require(Self.fixtureStore())
        let setlist = try #require(await store.setlist(forDate: "1977-05-08"))
        #expect(setlist.status == .full)
        #expect(setlist.sets.count >= 2)
        let allSongs = setlist.sets.flatMap(\.entries).map(\.songKey)
        #expect(allSongs.contains("scarlet begonias"))
    }

    @Test func ftsMatchesDateVariants() async throws {
        let store = try #require(Self.fixtureStore())
        for query in ["5-8-77", "5/8/77", "barton hall", "may 8 1977"] {
            let hits = await store.searchText(query, limit: 10)
            #expect(hits.contains { $0.date == "1977-05-08" }, "query \(query) missed Cornell")
        }
    }

    @Test func onThisDayIsInstantAndLocal() async throws {
        let store = try #require(Self.fixtureStore())
        let shows = await store.shows(onMonthDay: "05-08")
        #expect(shows.contains { $0.year == 1977 })
    }

    @Test func songPerformancesComeBackChronological() async throws {
        let store = try #require(Self.fixtureStore())
        let performances = await store.performances(ofSong: "scarlet begonias")
        #expect(!performances.isEmpty)
        let dates = performances.map(\.date)
        #expect(dates == dates.sorted())
    }
}

// MARK: - CatalogFirstShowProvider fallback behavior

struct CatalogFirstProviderTests {
    @Test func fallsBackWhenCatalogUnavailable() async throws {
        let mockCatalog = MockShowCatalog()
        mockCatalog.isAvailable = false
        let fallback = MockRecordingProvider()
        let provider = CatalogFirstShowProvider(catalog: mockCatalog, fallback: fallback)
        let shows = try await provider.onThisDay(monthDay: "05-08")
        #expect(!shows.isEmpty)   // mock provider's canned data
    }

    @Test func catalogAnswersOnThisDayWithoutNetwork() async throws {
        let mockCatalog = MockShowCatalog()
        mockCatalog.showsByID["1977-05-08"] = CatalogShow(
            showID: "1977-05-08", date: "1977-05-08", year: 1977, month: 5, day: 8,
            eraID: "hiatus-return", venue: "Barton Hall", city: "Ithaca", state: "NY",
            setlistStatus: .full, recordingCount: 3,
            bestIdentifier: "gd1977-05-08.sbd.test", bestSourceType: .soundboard,
            avgRating: 4.8, totalReviews: 500, totalDownloads: 100_000)
        let provider = CatalogFirstShowProvider(catalog: mockCatalog,
                                                fallback: FailingRecordingProvider())
        let shows = try await provider.onThisDay(monthDay: "05-08")
        #expect(shows.map(\.identifier) == ["gd1977-05-08.sbd.test"])
        #expect(shows.first?.venue == "Barton Hall")
    }

    @Test func recordingsForDateCarryVenueFromShow() async throws {
        let mockCatalog = MockShowCatalog()
        mockCatalog.showsByID["1977-05-08"] = CatalogShow(
            showID: "1977-05-08", date: "1977-05-08", year: 1977, month: 5, day: 8,
            eraID: nil, venue: "Barton Hall", city: "Ithaca", state: "NY",
            setlistStatus: .full, recordingCount: 1,
            bestIdentifier: "gd1977-05-08.sbd.test", bestSourceType: .soundboard,
            avgRating: 4.8, totalReviews: 500, totalDownloads: 100_000)
        mockCatalog.recordingsByShow["1977-05-08"] = [
            CatalogRecording(identifier: "gd1977-05-08.sbd.test", showID: "1977-05-08",
                             title: nil, sourceType: .soundboard, sourceText: "SBD> reel",
                             lineage: nil, taper: nil, avgRating: 4.8, numReviews: 500,
                             downloads: 100_000, qualityScore: 4048),
        ]
        let provider = CatalogFirstShowProvider(catalog: mockCatalog,
                                                fallback: FailingRecordingProvider())
        let shows = try await provider.recordings(forDate: "1977-05-08")
        #expect(shows.first?.venue == "Barton Hall")
        #expect(shows.first?.location == "Ithaca, NY")
    }
}

/// Throws on every call — proves the catalog path never touched the network.
private final class FailingRecordingProvider: LiveRecordingProvider {
    struct Unexpected: Error {}
    func shows(matching filters: SearchFilters) async throws -> [Show] { throw Unexpected() }
    func recordings(forDate day: String) async throws -> [Show] { throw Unexpected() }
    func topRated(yearRange: ClosedRange<Int>?, limit: Int) async throws -> [Show] { throw Unexpected() }
    func onThisDay(monthDay: String) async throws -> [Show] { throw Unexpected() }
}
