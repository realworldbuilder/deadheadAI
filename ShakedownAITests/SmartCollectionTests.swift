import Foundation
import Testing
@testable import ShakedownAI

// MARK: - Day context

struct DayContextTests {
    private func context(year: Int = 2026, month: Int, day: Int, hour: Int) -> DayContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        return DayContext(date: date, calendar: calendar)
    }

    @Test func daypartsSplitTheClock() {
        #expect(context(month: 8, day: 16, hour: 7).daypart == .morning)
        #expect(context(month: 8, day: 16, hour: 13).daypart == .afternoon)
        #expect(context(month: 8, day: 16, hour: 19).daypart == .evening)
        #expect(context(month: 8, day: 16, hour: 23).daypart == .lateNight)
        #expect(context(month: 8, day: 16, hour: 2).daypart == .lateNight)
    }

    @Test func seasonsFollowTourCycles() {
        #expect(context(month: 1, day: 5, hour: 12).season == .winter)
        #expect(context(month: 4, day: 5, hour: 12).season == .spring)
        #expect(context(month: 7, day: 5, hour: 12).season == .summer)
        #expect(context(month: 10, day: 5, hour: 12).season == .fall)
    }

    @Test func keyTurnsOverWithTheDayAndTheDaypart() {
        let morning = context(month: 8, day: 16, hour: 9)
        let evening = context(month: 8, day: 16, hour: 20)
        let tomorrow = context(month: 8, day: 17, hour: 9)
        #expect(morning.key != evening.key)
        #expect(morning.key != tomorrow.key)
        #expect(morning.key == context(month: 8, day: 16, hour: 10).key)
    }

    @Test func monthDayMatchesKnowledgeBaseFormat() {
        #expect(context(month: 5, day: 8, hour: 12).monthDay == "05-08")
        #expect(context(month: 12, day: 31, hour: 12).monthDay == "12-31")
    }
}

// MARK: - Trends

struct TrendEngineTests {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func event(_ song: String, daysAgo: Double, seconds: Double, year: Int = 1977,
                       identifier: String = "gd1977-05-08.sbd.hicks") -> TrendEngine.Event {
        TrendEngine.Event(songKey: song, showIdentifier: identifier, showYear: year,
                          startedAt: now.addingTimeInterval(-daysAgo * 24 * 3600), seconds: seconds)
    }

    @Test func emptyHistoryHasNoTrend() {
        #expect(TrendEngine.compute(events: [], now: now) == .empty)
    }

    @Test func songsPlayedMoreLatelyRise() {
        let events = [
            event("eyes of the world", daysAgo: 2, seconds: 900),
            event("eyes of the world", daysAgo: 5, seconds: 900),
            event("eyes of the world", daysAgo: 30, seconds: 300),
            event("truckin", daysAgo: 30, seconds: 1200),
            event("truckin", daysAgo: 3, seconds: 200),
        ]
        let trend = TrendEngine.compute(events: events, now: now)
        #expect(trend.risingSongKeys.first == "eyes of the world")
        #expect(!trend.risingSongKeys.contains("truckin"))
    }

    @Test func recentShowDatesComeOutOfArchiveIdentifiers() {
        let trend = TrendEngine.compute(events: [
            event("loser", daysAgo: 1, seconds: 400, identifier: "gd1977-05-08.sbd.hicks.4982"),
            event("loser", daysAgo: 40, seconds: 400, identifier: "gd1972-08-27.sbd.miller.97635"),
        ], now: now)
        #expect(trend.recentDates == ["1977-05-08"])
    }

    @Test func identifiersWithoutDatesAreIgnored() {
        #expect(TrendEngine.showDate(inIdentifier: "gd-unknown-source") == nil)
        #expect(TrendEngine.showDate(inIdentifier: "gd1973-02-15.sbd") == "1973-02-15")
    }

    @Test func eraMomentumTracksRecentListening() {
        let trend = TrendEngine.compute(events: [
            event("dark star", daysAgo: 1, seconds: 1800, year: 1969, identifier: "gd1969-02-27.sbd"),
            event("brokedown palace", daysAgo: 35, seconds: 600, year: 1980, identifier: "gd1980-09-25.sbd"),
        ], now: now)
        #expect(trend.risingEraID == "anthem")
    }
}

// MARK: - Planner

struct SmartCollectionPlannerTests {
    private let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)
    private var planner: SmartCollectionPlanner { SmartCollectionPlanner(knowledgeBase: kb) }

    private func context(month: Int, day: Int, hour: Int) -> DayContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        return DayContext(date: date, calendar: calendar)
    }

    @Test func everyShelfIsFilledWithRealShows() {
        let briefs = planner.briefs(context: context(month: 8, day: 16, hour: 20), taste: .empty, trend: .empty)
        #expect(briefs.count >= 3)
        for brief in briefs {
            #expect(!brief.fallbackTitle.isEmpty)
            #expect(!brief.rationale.isEmpty)
            #expect(brief.candidateDates.count >= 3 || brief.archiveQuery != nil)
            for date in brief.candidateDates {
                #expect(kb.notableShow(on: date) != nil, "\(brief.slotID) offered unknown show \(date)")
            }
        }
    }

    @Test func noShowAppearsOnTwoShelvesTheSameDay() {
        let briefs = planner.briefs(context: context(month: 3, day: 12, hour: 19), taste: .empty, trend: .empty)
        let all = briefs.flatMap(\.candidateDates)
        #expect(all.count == Set(all).count)
    }

    @Test func sameMomentPlansTheSameShelves() {
        let moment = context(month: 6, day: 4, hour: 14)
        #expect(planner.briefs(context: moment, taste: .empty, trend: .empty)
                == planner.briefs(context: moment, taste: .empty, trend: .empty))
    }

    @Test func theClockChangesTheFirstShelf() {
        let morning = planner.briefs(context: context(month: 8, day: 16, hour: 8), taste: .empty, trend: .empty)
        let lateNight = planner.briefs(context: context(month: 8, day: 16, hour: 23), taste: .empty, trend: .empty)
        let morningShelf = morning.first { $0.slotID == "daypart" }
        let lateShelf = lateNight.first { $0.slotID == "daypart" }
        #expect(morningShelf?.fallbackTitle != lateShelf?.fallbackTitle)
        #expect(lateShelf?.tags.contains("psychedelic") == true)
    }

    @Test func weekendEveningsGetTheHotShelf() {
        // 2026-08-14 is a Friday, 2026-08-18 a Tuesday.
        let friday = planner.briefs(context: context(month: 8, day: 14, hour: 20), taste: .empty, trend: .empty)
        #expect(friday.first { $0.slotID == "daypart" }?.tags.contains("high-energy") == true)
        let tuesday = planner.briefs(context: context(month: 8, day: 18, hour: 20), taste: .empty, trend: .empty)
        #expect(tuesday.first { $0.slotID == "daypart" }?.tags.contains("high-energy") != true)
    }

    @Test func consecutiveDaysServeDifferentShows() {
        let today = planner.briefs(context: context(month: 2, day: 10, hour: 20), taste: .empty, trend: .empty)
        let tomorrow = planner.briefs(context: context(month: 2, day: 11, hour: 20), taste: .empty, trend: .empty)
        let a = today.first { $0.slotID == "deep-cut" }?.candidateDates ?? []
        let b = tomorrow.first { $0.slotID == "deep-cut" }?.candidateDates ?? []
        #expect(a != b)
    }

    @Test func anniversariesTakeTheCalendarSlot() {
        // Cornell: the canon's most famous 5/8.
        let briefs = planner.briefs(context: context(month: 5, day: 8, hour: 20), taste: .empty, trend: .empty)
        let calendar = briefs.first { $0.slotID == "calendar" }
        #expect(calendar?.badge == "ON THIS DAY")
        #expect(calendar?.candidateDates.contains { $0.hasSuffix("-05-08") } == true)
    }

    @Test func aRisingSongBecomesItsOwnShelf() {
        guard let song = kb.songs.first(where: { $0.famousVersions.count >= 3 }) else { return }
        let trend = ListeningTrend(risingSongKeys: [song.key], risingEraID: nil,
                                   recentDates: [], recentSeconds: 9000)
        let briefs = planner.briefs(context: context(month: 9, day: 9, hour: 21), taste: .empty, trend: trend)
        let shelf = briefs.first { $0.slotID == "trend" }
        #expect(shelf?.badge == "RISING IN YOUR ROTATION")
        #expect(shelf?.fallbackTitle.contains(song.title) == true)
    }

    @Test func shelvesSkipWhatYouJustHeard() {
        let base = planner.select(tags: ["psychedelic"], limit: 5, rotation: 0,
                                  taste: .empty, excluding: [])
        guard let dropped = base.first else { return }
        let filtered = planner.select(tags: ["psychedelic"], limit: 5, rotation: 0,
                                      taste: .empty, excluding: [dropped])
        #expect(!filtered.prefix(3).contains(dropped))
    }

    @Test func tasteTiltsSelectionTowardYourEra() {
        // "brent" sits late in the canon, so a chronological tie-break alone
        // would never surface it — only the era weight can.
        let taste = TasteSnapshot(eraWeights: ["brent": 1.0], topSongKeys: [], favoriteVenues: [],
                                  totalSeconds: 20000, showsHeard: 12, exploredYears: [1985])
        let neutral = planner.select(tags: [], limit: 6, rotation: 0, taste: .empty, excluding: [])
        let tilted = planner.select(tags: [], limit: 6, rotation: 0, taste: taste, excluding: [])
        #expect(!neutral.contains { kb.notableShow(on: $0)?.eraID == "brent" })
        #expect(tilted.allSatisfy { kb.notableShow(on: $0)?.eraID == "brent" })
    }

    @Test func newListenersStillGetATrendShelfFromTheArchive() {
        let briefs = planner.briefs(context: context(month: 11, day: 2, hour: 16), taste: .empty, trend: .empty)
        let shelf = briefs.first { $0.slotID == "trend" }
        #expect(shelf?.archiveQuery != nil)
        #expect(shelf?.archiveQuery?.yearRange != nil)
    }
}

// MARK: - Offline curation

struct SmartCollectionCuratorTests {
    private let brief = CollectionBrief(
        slotID: "daypart", badge: "LATE NIGHT", fallbackTitle: "The Small Hours",
        iconName: "moon.stars.fill", rationale: "Everyone else is asleep.",
        tags: ["psychedelic"], candidateDates: [], archiveQuery: nil
    )

    private func candidate(_ date: String, songs: [String] = [], blurb: String = "") -> CollectionCandidate {
        CollectionCandidate(date: date, venue: "Fillmore East", location: "New York, NY",
                            eraName: "Anthem", tags: ["psychedelic"], blurb: blurb,
                            standoutSongs: songs, identifier: nil, rating: nil)
    }

    @Test func curationOnlyShelvesOfferedShows() {
        let candidates = [candidate("1970-02-13", songs: ["Dark Star"]), candidate("1969-02-27")]
        let curated = SmartCollectionCurator.curate(brief: brief, candidates: candidates)
        #expect(Set(curated.picks.map(\.date)).isSubset(of: Set(candidates.map(\.date))))
        #expect(curated.title == brief.fallbackTitle)
        #expect(!curated.picks.contains { $0.note.isEmpty })
    }

    @Test func notesPreferConcreteDetail() {
        #expect(SmartCollectionCurator.note(for: candidate("1970-02-13", songs: ["Dark Star"]))
                == "Listen for Dark Star.")
        #expect(SmartCollectionCurator.note(for: candidate("1970-02-13", blurb: "A furious night. And more."))
                == "A furious night.")
    }

    @Test func curationRespectsTheLimit() {
        let candidates = (1...9).map { candidate("1977-05-0\($0)") }
        #expect(SmartCollectionCurator.curate(brief: brief, candidates: candidates).picks.count == 5)
    }
}

// MARK: - End-to-end shelf building

@MainActor
struct SmartCollectionEngineTests {
    private func makeEnvironment() -> AppEnvironment {
        let recording = MockRecordingProvider()
        return AppEnvironment(
            modelContainer: ModelContainerFactory.make(inMemory: true),
            knowledgeBase: KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle),
            recordingProvider: recording,
            metadataProvider: recording,
            streamingProvider: MockStreamingProvider(),
            aiProvider: MockAIProvider(),
            authProvider: MockAuthProvider()
        )
    }

    @Test func buildsFullShelvesFromScratch() async {
        let engine = SmartCollectionEngine(env: makeEnvironment())
        await engine.refresh()

        #expect(engine.collections.count >= 3)
        #expect(Set(engine.collections.map(\.slotID)).count == engine.collections.count)
        for collection in engine.collections {
            #expect(!collection.title.isEmpty)
            #expect(!collection.blurb.isEmpty)
            #expect(collection.items.count >= 3)
            #expect(collection.items.allSatisfy { !$0.note.isEmpty })
            #expect(Set(collection.items.map(\.date)).count == collection.items.count)
        }
    }

    @Test func cachedShelvesAreReusedUntilTheDaypartTurns() async {
        let engine = SmartCollectionEngine(env: makeEnvironment())
        await engine.refresh()
        let stamps = engine.collections.map(\.generatedAt)

        await engine.refreshIfNeeded()
        #expect(engine.collections.map(\.generatedAt) == stamps)
    }

    @Test func shelvesSurviveARestart() async {
        let env = makeEnvironment()
        await SmartCollectionEngine(env: env).refresh()
        let titles = env.smartCollections.collections.map(\.title)

        // A second store over the same container is what relaunching looks like.
        let reloaded = SmartCollectionStore(container: env.modelContainer)
        #expect(reloaded.collections.map(\.title) == titles)
        #expect(!reloaded.needsRefresh(for: DayContext().key))
    }

    @Test func pinningCopiesAShelfIntoTheLibrary() async {
        let env = makeEnvironment()
        let engine = SmartCollectionEngine(env: env)
        await engine.refresh()
        guard let shelf = engine.collections.first else {
            Issue.record("no shelves to pin")
            return
        }

        let saved = await engine.pinToLibrary(shelf)
        #expect(saved.name == shelf.title)
        #expect(!(saved.items ?? []).isEmpty)
        #expect(env.library.collections.contains { $0.name == shelf.title })
    }
}
