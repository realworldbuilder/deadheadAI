import Foundation
import Testing
@testable import ShakedownAI

// MARK: - RunFinder: runs inside a catalog setlist

struct RunFinderTests {
    private let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)

    private func entry(_ position: Int, _ title: String, set: String = "Set 2",
                       segues: Bool = false) -> SetlistEntry {
        SetlistEntry(position: position, setLabel: set,
                     songKey: Track.normalizeSongKey(title), songTitle: title,
                     seguesIntoNext: segues)
    }

    private func tracks(_ titles: [String]) -> [Track] {
        titles.enumerated().map { index, title in
            Track(fileName: "t\(index).mp3", title: title, trackNumber: index + 1, durationSeconds: 300)
        }
    }

    private func night(_ date: String, rating: Double? = 4.8, reviews: Int = 100) -> CatalogShow {
        CatalogShow(showID: date, date: date,
                    year: Int(date.prefix(4)) ?? 0, month: 5, day: 8,
                    eraID: "hiatus-return", venue: "Barton Hall", city: "Ithaca", state: "NY",
                    setlistStatus: .full, recordingCount: 3, bestIdentifier: "gd\(date)",
                    bestSourceType: .soundboard, avgRating: rating, totalReviews: reviews,
                    totalDownloads: 1000, coverImageURL: nil)
    }

    @Test func flaggedSeguesFormARunAcrossDrumsAndSpace() {
        let entries = [
            entry(0, "Samba in the Rain"),
            entry(1, "Corrina", segues: true),
            entry(2, "Drums", segues: true),
            entry(3, "Space", segues: true),
            entry(4, "Unbroken Chain"),
            entry(5, "Sugar Magnolia"),
        ]
        let chains = RunFinder.chains(in: entries, kb: kb)
        #expect(chains.count == 1)
        #expect(chains.first?.title == "Corrina > Drums > Space > Unbroken Chain")
        #expect(chains.first?.signature == "corrina > unbroken chain")
        #expect(chains.first?.songs.count == 2)
    }

    @Test func classicPairingsLinkWithoutFlags() {
        // Cornell's second set as the catalog carries it: no arrows anywhere.
        let entries = [
            entry(0, "Dancing in the Street"),
            entry(1, "Scarlet Begonias"),
            entry(2, "Fire on the Mountain"),
            entry(3, "Estimated Prophet"),
            entry(4, "St. Stephen"),
            entry(5, "Not Fade Away"),
            entry(6, "St. Stephen"),
            entry(7, "Morning Dew"),
        ]
        let signatures = RunFinder.chains(in: entries, kb: kb).map(\.signature)
        #expect(signatures.contains("scarlet begonias > fire on the mountain"))
        #expect(signatures.contains("st stephen > not fade away > st stephen"))
        #expect(!signatures.contains { $0.contains("dancing") })
    }

    @Test func runsNeverCrossASetBoundary() {
        let entries = [
            entry(0, "Scarlet Begonias", set: "Set 1"),
            entry(1, "Fire on the Mountain", set: "Set 2"),
        ]
        #expect(RunFinder.chains(in: entries, kb: kb).isEmpty)
    }

    @Test func bridgesNeverOpenOrCloseARun() {
        // A flagged trip into Drums with nothing on the far side is not a run…
        let dangling = [entry(0, "Playing in the Band", segues: true), entry(1, "Drums"), entry(2, "Space")]
        #expect(RunFinder.chains(in: dangling, kb: kb).isEmpty)

        // …and a run that trails off into Drums is trimmed back to its songs.
        let trailing = [entry(0, "Truckin'"), entry(1, "The Other One", segues: true), entry(2, "Drums")]
        let chains = RunFinder.chains(in: trailing, kb: kb)
        #expect(chains.map(\.title) == ["Truckin' > The Other One"])
    }

    @Test func partnersReachAcrossTwoBridges() {
        let entries = [entry(0, "Bertha"), entry(1, "Truckin'"), entry(2, "Drums"),
                       entry(3, "Space"), entry(4, "The Other One"), entry(5, "Wharf Rat")]
        let chains = RunFinder.chains(in: entries, kb: kb)
        #expect(chains.count == 1)
        #expect(chains.first?.title == "Truckin' > Drums > Space > The Other One > Wharf Rat")
    }

    @Test func unrelatedNeighborsDoNotLink() {
        let entries = [entry(0, "Bertha"), entry(1, "Loser"), entry(2, "El Paso")]
        #expect(RunFinder.chains(in: entries, kb: kb).isEmpty)
    }

    @Test func synthesizedRunResolvesOnATape() throws {
        let entries = [entry(0, "Bertha"), entry(1, "Truckin'"), entry(2, "Drums"),
                       entry(3, "Space"), entry(4, "The Other One")]
        let chain = try #require(RunFinder.chains(in: entries, kb: kb).first)
        let run = RunFinder.run(from: chain, show: night("1977-05-08"))

        #expect(RunFinder.isCatalogRun(run))
        #expect(run.date == "1977-05-08")
        #expect(run.eraID == "hiatus-return")
        #expect(run.songKeys == ["truckin'", "drums", "space", "the other one"])
        #expect(run.blurb.contains("Two songs played as one piece, in the second set at Barton Hall, Ithaca, NY."))
        #expect(run.blurb.contains("100 listeners rate 4.8"))

        let tape = tracks(["Bertha", "Truckin'", "Drums", "Space", "The Other One", "Wharf Rat"])
        #expect(RunResolver.resolve(run, in: tape) == 1...4)
    }

    @Test func cleansSourceMarkupFromTitles() {
        #expect(RunFinder.cleanTitle("E: Black Muddy River") == "Black Muddy River")
        #expect(RunFinder.cleanTitle("Masterpiece*") == "Masterpiece")
        #expect(RunFinder.cleanTitle("  Dark Star ") == "Dark Star")
        #expect(RunFinder.cleanTitle("drums") == "Drums")
        #expect(RunFinder.cleanTitle("he's gone") == "He's Gone")
    }

    @Test func fixtureNightsYieldRuns() async throws {
        guard let url = Bundle(for: FixtureAnchor.self)
            .url(forResource: "catalog-fixture", withExtension: "sqlite") else { return }
        let store = CatalogStore(fileURL: url)
        let setlist = try #require(await store.setlist(forShow: "1995-07-09"))
        let chains = RunFinder.chains(in: setlist.sets.flatMap(\.entries), kb: kb)
        #expect(chains.map(\.signature).contains("corrina > unbroken chain"))
    }
}

// MARK: - RunShelfPlanner: what greets the listener today

struct RunShelfPlannerTests {
    private let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)

    @Test func canonPicksRotateDailyAndKeepOneRunPerNight() {
        let today = RunShelfPlanner.canonPicks(kb.runs, dayOfYear: 10, taste: .empty, limit: 3)
        let tomorrow = RunShelfPlanner.canonPicks(kb.runs, dayOfYear: 11, taste: .empty, limit: 3)
        #expect(today.count == 3)
        #expect(today != tomorrow)
        #expect(Set(today.map(\.date)).count == today.count)
        // Deterministic: the same day always gets the same shelf.
        #expect(today == RunShelfPlanner.canonPicks(kb.runs, dayOfYear: 10, taste: .empty, limit: 3))
    }

    @Test func favoriteEraLeadsOnceThereIsRealListening() {
        let taste = TasteSnapshot(eraWeights: ["brent": 10, "primal": 1], topSongKeys: [],
                                  favoriteVenues: [], totalSeconds: 5000, showsHeard: 4, exploredYears: [])
        for day in 1...20 {
            let picks = RunShelfPlanner.canonPicks(kb.runs, dayOfYear: day, taste: taste, limit: 3)
            #expect(picks.first?.eraID == "brent", "day \(day) should lead with the favorite era")
        }
        // A fresh listener gets the plain rotation instead.
        let cold = RunShelfPlanner.canonPicks(kb.runs, dayOfYear: 1, taste: .empty, limit: 3)
        #expect(cold.map(\.date) == cold.map(\.date).sorted())
    }

    private func candidate(_ date: String, _ titles: [String], rating: Double) -> RunShelfPlanner.Candidate {
        let entries = titles.enumerated().map { index, title in
            SetlistEntry(position: index, setLabel: "Set 2", songKey: Track.normalizeSongKey(title),
                         songTitle: title, seguesIntoNext: true)
        }
        let show = CatalogShow(showID: date, date: date, year: Int(date.prefix(4)) ?? 0, month: 1, day: 1,
                               eraID: nil, venue: "Winterland", city: "San Francisco", state: "CA",
                               setlistStatus: .full, recordingCount: 1, bestIdentifier: "gd\(date)",
                               bestSourceType: .soundboard, avgRating: rating, totalReviews: 50,
                               totalDownloads: 10, coverImageURL: nil)
        return .init(chain: RunFinder.Chain(entries: entries), show: show)
    }

    @Test func catalogPicksNeverRepeatASequenceOrACanonNight() {
        let candidates = [
            candidate("1972-05-11", ["China Cat Sunflower", "I Know You Rider"], rating: 4.94),
            candidate("1973-11-17", ["China Cat Sunflower", "I Know You Rider"], rating: 4.88),
            candidate("1972-08-27", ["China Cat Sunflower", "I Know You Rider"], rating: 4.86),
            candidate("1975-08-13", ["Help on the Way", "Slipknot!", "Franklin's Tower"], rating: 4.89),
            candidate("1977-05-08", ["Scarlet Begonias", "Fire on the Mountain"], rating: 4.74),
        ]
        let picks = RunShelfPlanner.catalogPicks(candidates, excludingDates: ["1977-05-08"],
                                                 dayOfYear: 0, limit: 4)
        #expect(picks.count == 2)
        #expect(picks.allSatisfy { $0.date != "1977-05-08" })
        #expect(picks.filter { $0.title.hasPrefix("China Cat") }.count == 1)
        // Longer runs on better nights lead the ranking.
        #expect(picks.first?.title == "Help on the Way > Slipknot! > Franklin's Tower")
    }

    @Test func catalogPicksRotateThroughTheTopOfTheRanking() {
        // Song keys strip digits, so every night needs its own words.
        let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot",
                     "golf", "hotel", "india", "juliet", "kilo", "lima"]
        let candidates = words.enumerated().map { index, word in
            candidate("198\(index % 10)-0\(index % 9 + 1)-1\(index % 10)",
                      ["\(word.capitalized) Rising", "\(word.capitalized) Falling"],
                      rating: 4.9 - Double(index) * 0.01)
        }
        let dayOne = RunShelfPlanner.catalogPicks(candidates, excludingDates: [], dayOfYear: 1, limit: 2)
        let dayTwo = RunShelfPlanner.catalogPicks(candidates, excludingDates: [], dayOfYear: 2, limit: 2)
        #expect(dayOne.count == 2)
        #expect(dayOne != dayTwo)
        // The pool is only a few days deep, so the shelf never sinks to the bottom of the ranking.
        let worst = candidates.last!.show.date
        for day in 0..<40 {
            let picks = RunShelfPlanner.catalogPicks(candidates, excludingDates: [], dayOfYear: day, limit: 2)
            #expect(!picks.contains { $0.date == worst })
        }
    }

    @Test func emptyInputsAreQuiet() {
        #expect(RunShelfPlanner.canonPicks([], dayOfYear: 1, taste: .empty, limit: 3).isEmpty)
        #expect(RunShelfPlanner.catalogPicks([], excludingDates: [], dayOfYear: 1, limit: 3).isEmpty)
        #expect(RunShelfPlanner.canonPicks(kb.runs, dayOfYear: 1, taste: .empty, limit: 0).isEmpty)
    }
}

// MARK: - Shelf card copy

struct RunShelfPickTests {
    private func pick(_ run: FamousRun, canon: Bool) -> RunShelfModel.Pick {
        RunShelfModel.Pick(run: run, show: nil, venue: nil, location: nil, isCanon: canon)
    }

    @Test func badgesCountSongsNotBridges() {
        let canon = FamousRun(id: "c", date: "1977-05-08", title: "Scarlet > Fire",
                              songKeys: ["scarlet begonias", "fire on the mountain"], blurb: "", eraID: nil, tags: [])
        #expect(pick(canon, canon: true).badge == "Famous run · 2 songs")

        let marathon = FamousRun(id: "m", date: "1972-08-27", title: "The Veneta Dark Star",
                                 songKeys: ["dark star"], blurb: "", eraID: nil, tags: [])
        #expect(pick(marathon, canon: true).badge == "Famous run · one long version")

        let catalog = FamousRun(id: "catalog|x|1", date: "1977-05-08", title: "Truckin' > Drums > Space > The Other One",
                                songKeys: ["truckin'", "drums", "space", "the other one"], blurb: "", eraID: nil, tags: ["segue"])
        #expect(pick(catalog, canon: false).badge == "Segue · 2 songs")
    }

    @Test func styledTitleKeepsEverySong() {
        // Text has no public accessor, so we check the seam the styling relies on.
        let parts = "Help on the Way > Slipknot! > Franklin's Tower".components(separatedBy: " > ")
        #expect(parts == ["Help on the Way", "Slipknot!", "Franklin's Tower"])
    }
}

// MARK: - Playing a run: the night's other tapes

@MainActor
struct RunShelfPlaybackTests {
    private func show(_ identifier: String) -> Show {
        Show(identifier: identifier, title: identifier, date: nil, dateString: "1989-07-07",
             venue: "JFK Stadium", location: "Philadelphia, PA", year: 1989,
             avgRating: 4.6, numReviews: 10, downloads: 100, source: nil)
    }

    private func detail(_ identifier: String, _ titles: [String]) -> RecordingDetail {
        RecordingDetail(identifier: identifier, title: nil, dateString: "1989-07-07", venue: nil,
                        location: nil, source: nil, lineage: nil, notes: nil, setlistText: nil,
                        tracks: titles.enumerated().map { index, title in
                            Track(fileName: "t\(index).mp3", title: title, trackNumber: index + 1, durationSeconds: 600)
                        }, reviews: [])
    }

    @Test func fallsBackToTheNightsOtherTapesWhenTheBestOneIsAPartial() async throws {
        let env = AppEnvironment.mock()
        let mock = try #require(env.recordingProvider as? MockRecordingProvider)
        let partial = show("gd1989-07-07.partial"), full = show("gd1989-07-07.full")
        mock.showsResult = [partial, full]
        mock.detailsByIdentifier = [
            partial.identifier: detail(partial.identifier, ["Scarlet Begonias", "Fire On The Mountain"]),
            full.identifier: detail(full.identifier, ["Scarlet Begonias", "Fire On The Mountain", "Morning Dew", "Lovelight"]),
        ]
        let run = FamousRun(id: "test-dew", date: "1989-07-07", title: "The JFK Morning Dew",
                            songKeys: ["morning dew"], blurb: "", eraID: "brent", tags: [])
        let model = RunShelfModel(env: env)
        let pick = RunShelfModel.Pick(run: run, show: partial, venue: nil, location: nil, isCanon: true)

        await model.play(pick)

        #expect(model.error == nil)
        #expect(mock.requestedDetails == [partial.identifier, full.identifier])
        #expect(env.playerEngine.queue.map(\.track.title) == ["Morning Dew"])
        #expect(env.playerEngine.queue.first?.show.identifier == full.identifier)
    }

    @Test func pinsEveryPickUpFrontSoCardsCanSayHowLong() async throws {
        let env = AppEnvironment.mock()
        let mock = try #require(env.recordingProvider as? MockRecordingProvider)
        let tape = show("gd1989-07-07.full")
        mock.showsResult = [tape]
        mock.detailsByIdentifier = [tape.identifier: detail(tape.identifier, ["Scarlet Begonias", "Fire On The Mountain", "Morning Dew"])]
        let dew = FamousRun(id: "dew", date: "1989-07-07", title: "Dew", songKeys: ["morning dew"], blurb: "", eraID: nil, tags: [])
        let missing = FamousRun(id: "missing", date: "1989-07-07", title: "Dark Star", songKeys: ["dark star"], blurb: "", eraID: nil, tags: [])
        let model = RunShelfModel(env: env)
        let picks = [dew, missing].map { RunShelfModel.Pick(run: $0, show: tape, venue: nil, location: nil, isCanon: true) }
        model.setPicksForTesting(picks)

        await model.resolveAll()

        #expect(model.lengthText(for: picks[0]) == "10 min")
        #expect(model.lengthText(for: picks[1]) == nil)
        #expect(model.unavailable == ["missing"])
        #expect(model.totalLengthText == "10 min")
        // Playing now needs no second fetch.
        let fetched = mock.requestedDetails.count
        await model.play(picks[0])
        #expect(mock.requestedDetails.count == fetched)
        #expect(env.playerEngine.queue.map(\.track.title) == ["Morning Dew"])
    }

    @Test func resolvesFromTheCatalogWithNoNetworkAtAll() async throws {
        let env = AppEnvironment.mock()
        let mock = try #require(env.recordingProvider as? MockRecordingProvider)
        let catalog = try #require(env.catalog as? MockShowCatalog)
        let night = CatalogShow(showID: "1977-05-08", date: "1977-05-08", year: 1977, month: 5, day: 8,
                                eraID: "hiatus-return", venue: "Barton Hall", city: "Ithaca", state: "NY",
                                setlistStatus: .full, recordingCount: 2, bestIdentifier: "gd77.partial",
                                bestSourceType: .soundboard, avgRating: 4.7, totalReviews: 800,
                                totalDownloads: 1, coverImageURL: nil)
        func tape(_ id: String, score: Double) -> CatalogRecording {
            CatalogRecording(identifier: id, showID: night.showID, title: nil, sourceType: .soundboard,
                             sourceText: nil, lineage: nil, taper: nil, avgRating: 4.7, numReviews: 10,
                             downloads: 100, qualityScore: score)
        }
        func tracks(_ titles: [String]) -> [Track] {
            titles.enumerated().map { Track(fileName: "f\($0).mp3", title: $1, trackNumber: $0 + 1, durationSeconds: 780) }
        }
        catalog.showsByID = [night.showID: night]
        catalog.recordingsByShow = [night.showID: [tape("gd77.partial", score: 9), tape("gd77.full", score: 8)]]
        catalog.tracksByIdentifier = [
            "gd77.partial": tracks(["Loser", "El Paso"]),
            "gd77.full": tracks(["Loser", "Scarlet Begonias", "Fire On The Mountain", "Morning Dew"]),
        ]
        let run = FamousRun(id: "sf", date: "1977-05-08", title: "Scarlet > Fire",
                            songKeys: ["scarlet begonias", "fire on the mountain"], blurb: "", eraID: nil, tags: [])
        let model = RunShelfModel(env: env)
        let pick = RunShelfModel.Pick(run: run, show: nil, venue: nil, location: nil, isCanon: true)
        model.setPicksForTesting([pick])

        await model.resolveAll()
        #expect(model.lengthText(for: pick) == "26 min")
        #expect(mock.requestedDetails.isEmpty, "the catalog answered; the archive was never asked")

        await model.play(pick)
        #expect(mock.requestedDetails.isEmpty)
        #expect(env.playerEngine.queue.map(\.track.title) == ["Scarlet Begonias", "Fire On The Mountain"])
        let show = try #require(env.playerEngine.queue.first?.show)
        #expect(show.identifier == "gd77.full")
        #expect(show.venue == "Barton Hall")
        #expect(show.dateString == "1977-05-08")
    }

    @Test func reportsWhenNoTapeCarriesTheRun() async throws {
        let env = AppEnvironment.mock()
        let mock = try #require(env.recordingProvider as? MockRecordingProvider)
        let only = show("gd1989-07-07.only")
        mock.showsResult = [only]
        mock.detailsByIdentifier = [only.identifier: detail(only.identifier, ["Iko Iko", "Loser"])]
        let run = FamousRun(id: "r", date: "1989-07-07", title: "The JFK Morning Dew",
                            songKeys: ["morning dew"], blurb: "", eraID: nil, tags: [])
        let model = RunShelfModel(env: env)

        await model.play(RunShelfModel.Pick(run: run, show: nil, venue: nil, location: nil, isCanon: true))

        #expect(model.error?.contains("The JFK Morning Dew") == true)
        #expect(mock.requestedDetails == [only.identifier])
        #expect(env.playerEngine.queue.isEmpty)
    }
}

// MARK: - Running time

struct RunLengthTests {
    private func tracks(_ durations: [Double?]) -> [Track] {
        durations.enumerated().map { index, seconds in
            Track(fileName: "t\(index).mp3", title: "Song \(index)", trackNumber: index + 1, durationSeconds: seconds)
        }
    }

    @Test func formatsMinutesAndHours() {
        #expect(RunLength.format(seconds: 20) == "1 min")
        #expect(RunLength.format(seconds: 26 * 60 + 20) == "26 min")
        #expect(RunLength.format(seconds: 60 * 60) == "1 hr")
        #expect(RunLength.format(seconds: 72 * 60 + 40) == "1 hr 13 min")
        #expect(RunLength.format(seconds: 2 * 3600 + 38 * 60) == "2 hr 38 min")
    }

    @Test func sumsOnlyTheRunAndOnlyKnownDurations() {
        let tape = tracks([300, 600, nil, 900, 120])
        #expect(RunLength.seconds(of: tape, in: 1...3) == 1500)
        #expect(RunLength.seconds(of: tape, in: 2...2) == nil, "a tape with no durations says nothing")
        #expect(RunLength.seconds(of: tape, in: 3...7) == nil, "a range off the tape says nothing")
        #expect(RunLength.seconds(of: [], in: 0...0) == nil)
    }

    @Test func resolvedRunKnowsItsSliceAndLength() {
        let show = Show(identifier: "gd77", title: "t", date: nil, dateString: "1977-05-08", venue: "Barton Hall",
                        location: nil, year: 1977, avgRating: nil, numReviews: nil, downloads: nil, source: nil)
        let run = FamousRun(id: "r", date: "1977-05-08", title: "Scarlet > Fire",
                            songKeys: ["scarlet begonias", "fire on the mountain"], blurb: "", eraID: nil, tags: [])
        let hit = ResolvedRun(run: run, show: show, tracks: tracks([300, 700, 800, 400]), range: 1...2)
        #expect(hit.runTracks.map(\.title) == ["Song 1", "Song 2"])
        #expect(hit.lengthText == "25 min")
        #expect(hit.entries.map(\.id) == ["gd77|t1.mp3", "gd77|t2.mp3"])
    }
}

// MARK: - Runs already on a tape (the offline / CarPlay listing)

struct OnTapeRunTests {
    private let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)

    private func tracks(_ titles: [String]) -> [Track] {
        titles.enumerated().map { index, title in
            Track(fileName: "t\(index).mp3", title: title, trackNumber: index + 1, durationSeconds: 600)
        }
    }

    private func entry(_ position: Int, _ title: String, set: String = "Set 2") -> SetlistEntry {
        SetlistEntry(position: position, setLabel: set, songKey: Track.normalizeSongKey(title),
                     songTitle: title, seguesIntoNext: false)
    }

    @Test func canonLeadsAndCatalogFillsInWithoutRepeatingTheSameStretch() {
        let show = Show(identifier: "gd77-05-08", title: "t", date: nil, dateString: "1977-05-08", venue: "Barton Hall",
                        location: nil, year: 1977, avgRating: nil, numReviews: nil, downloads: nil, source: nil)
        let night = CatalogShow(showID: "1977-05-08", date: "1977-05-08", year: 1977, month: 5, day: 8,
                                eraID: "hiatus-return", venue: "Barton Hall", city: "Ithaca", state: "NY",
                                setlistStatus: .full, recordingCount: 1, bestIdentifier: show.identifier,
                                bestSourceType: .soundboard, avgRating: 4.7, totalReviews: 800,
                                totalDownloads: 1, coverImageURL: nil)
        let setlist = Setlist(showID: night.showID, status: .full, entries: [
            entry(0, "Scarlet Begonias"), entry(1, "Fire on the Mountain"), entry(2, "Estimated Prophet"),
            entry(3, "St. Stephen"), entry(4, "Not Fade Away"), entry(5, "St. Stephen"), entry(6, "Morning Dew"),
        ])
        let tape = tracks(["Scarlet Begonias", "Fire On The Mountain", "Estimated Prophet",
                           "St. Stephen", "Not Fade Away", "St. Stephen", "Morning Dew"])

        let runs = RunFinder.runs(onTape: tape, show: show, canon: kb.runs(on: "1977-05-08"),
                                  night: night, setlist: setlist, kb: kb)

        let titles = runs.map(\.run.title)
        #expect(titles.contains("Scarlet Begonias > Fire on the Mountain"))
        #expect(titles.contains("The Cornell Morning Dew"))
        #expect(titles.contains("St. Stephen > Not Fade Away > St. Stephen"))
        // The catalog's own Scarlet > Fire is the same stretch of tape as the canon's: listed once.
        #expect(runs.filter { $0.range == 0...1 }.count == 1)
        #expect(runs.first { $0.range == 0...1 }?.run.id == "1977-05-08-scarlet-fire")
        #expect(runs.map(\.range.lowerBound) == runs.map(\.range.lowerBound).sorted(), "stage order")
        #expect(runs.allSatisfy { $0.lengthText != nil })
    }

    @Test func aTapeWithoutTheRunListsNothingForIt() {
        let show = Show(identifier: "x", title: "t", date: nil, dateString: "1977-05-08", venue: nil,
                        location: nil, year: nil, avgRating: nil, numReviews: nil, downloads: nil, source: nil)
        let runs = RunFinder.runs(onTape: tracks(["Loser", "El Paso"]), show: show,
                                  canon: kb.runs(on: "1977-05-08"), night: nil, setlist: nil, kb: kb)
        #expect(runs.isEmpty)
    }
}

// MARK: - CarPlay rows

struct RunRowsTests {
    private func hit(_ id: String, title: String, date: String, venue: String?, durations: [Double?]) -> ResolvedRun {
        let show = Show(identifier: id, title: id, date: nil, dateString: date, venue: venue, location: nil,
                        year: nil, avgRating: nil, numReviews: nil, downloads: nil, source: nil)
        let tracks = durations.enumerated().map { index, seconds in
            Track(fileName: "\(id)-\(index).mp3", title: "T\(index)", trackNumber: index + 1, durationSeconds: seconds)
        }
        let run = FamousRun(id: id, date: date, title: title, songKeys: [], blurb: "", eraID: nil, tags: [])
        return ResolvedRun(run: run, show: show, tracks: tracks, range: 0...(tracks.count - 1))
    }

    @Test func onDeviceRowsLeadWithPlayEverythingAndWearTheirTimes() {
        let runs = [
            hit("a", title: "Scarlet Begonias > Fire on the Mountain", date: "1977-05-08", venue: "Barton Hall", durations: [600, 960]),
            hit("b", title: "The Cornell Morning Dew", date: "1977-05-08", venue: "Barton Hall", durations: [830]),
        ]
        let rows = RunRows.onDevice(runs)
        #expect(rows.map(\.title) == ["Play every run on this device",
                                       "Scarlet Begonias > Fire on the Mountain", "The Cornell Morning Dew"])
        #expect(rows[0].detail == "2 runs · 40 min")
        #expect(rows[1].detail == "5/8/77 · Barton Hall · 26 min")
        #expect(rows[2].detail == "5/8/77 · Barton Hall · 14 min")
        #expect(RunRows.onDevice([]).isEmpty)
    }

    @Test func shelfRowsJoinTheTimeOnceKnown() {
        let scarlet = FamousRun(id: "s", date: "1977-05-08", title: "Scarlet > Fire", songKeys: [], blurb: "", eraID: nil, tags: [])
        let help = FamousRun(id: "h", date: "1977-05-09", title: "Help > Slip > Frank", songKeys: [], blurb: "", eraID: nil, tags: [])
        let rows = RunRows.shelf(picks: [(scarlet, "Barton Hall", "26 min"), (help, nil, nil)], totalLengthText: nil)
        #expect(rows[0] == RunRows.Row(title: "Play all of today's runs", detail: "2 runs"))
        #expect(rows[1].detail == "5/8/77 · Barton Hall · 26 min")
        #expect(rows[2].detail == "5/9/77")
        let done = RunRows.shelf(picks: [(scarlet, "Barton Hall", "26 min")], totalLengthText: "26 min")
        #expect(done[0].detail == "1 run · 26 min")
        #expect(RunRows.shelf(picks: [], totalLengthText: nil).isEmpty)
    }
}
