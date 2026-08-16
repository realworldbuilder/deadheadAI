import Foundation
import Testing
@testable import ShakedownAI

// MARK: - Knowledge base integrity

struct KnowledgeBaseTests {
    private let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)

    @Test func bundleContentLoads() {
        #expect(kb.notableShows.count > 50)
        #expect(kb.songs.count > 40)
        #expect(kb.eras.count == 7)
        #expect(kb.journeys.count == 6)
        #expect(!kb.quotes.isEmpty)
    }

    @Test func erasCoverEveryTouringYearExactlyOnce() {
        for year in 1965...1995 {
            let matching = kb.eras.filter { ($0.startYear...$0.endYear).contains(year) }
            #expect(matching.count == 1, "year \(year) covered by \(matching.count) eras")
        }
    }

    @Test func everyShowBelongsToARealEraAndParses() {
        let eraIDs = Set(kb.eras.map(\.id))
        for show in kb.notableShows {
            #expect(eraIDs.contains(show.eraID), "\(show.date) has unknown era \(show.eraID)")
            #expect(IADates.parse(show.date) != nil, "\(show.date) unparseable")
            #expect(!show.blurb.isEmpty)
            #expect(!show.tags.isEmpty)
        }
    }

    @Test func eraShowReferencesResolve() {
        for era in kb.eras {
            for date in era.beginnerShows + era.mustHear {
                #expect(kb.notableShow(on: date) != nil, "era \(era.id) references missing show \(date)")
            }
        }
    }

    @Test func journeyDatesAreValidAndDaysNonEmpty() {
        for journey in kb.journeys {
            #expect(journey.days.count >= 5)
            for day in journey.days {
                #expect(IADates.parse(day.showDate) != nil, "\(journey.id): bad date \(day.showDate)")
                #expect(!day.essay.isEmpty)
                #expect(!day.journalPrompt.isEmpty)
            }
        }
    }

    @Test func heroRotatesAndIsDeterministic() {
        let a = kb.heroShow(dayOfYear: 40, taste: .empty)
        let b = kb.heroShow(dayOfYear: 40, taste: .empty)
        let c = kb.heroShow(dayOfYear: 41, taste: .empty)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func relatedShowsShareSomething() {
        guard let cornell = kb.notableShow(on: "1977-05-08") else {
            Issue.record("Cornell missing from KB")
            return
        }
        let related = kb.related(to: cornell, limit: 5)
        #expect(!related.isEmpty)
        #expect(!related.contains(cornell))
        for show in related {
            #expect(kb.affinity(cornell, show) > 0)
        }
    }
}

// MARK: - Local AI

struct LocalKnowledgeAITests {
    private let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)
    private var ai: LocalKnowledgeAI { LocalKnowledgeAI(knowledgeBase: kb) }

    @Test func parsesYearQueries() async throws {
        let filters = try await ai.parseSearchIntent("best shows from 1977")
        #expect(filters.yearRange == 1977...1977)
        #expect(filters.sortByRating == true)
    }

    @Test func parsesShorthandAndDecades() {
        #expect(LocalKnowledgeAI.years(inQuery: "primal '68 energy") == 1968...1968)
        #expect(LocalKnowledgeAI.years(inQuery: "give me the 80s") == 1980...1989)
        #expect(LocalKnowledgeAI.years(inQuery: "1972 to 1974 jams") == 1972...1974)
    }

    @Test func parsesMoodTags() {
        #expect(LocalKnowledgeAI.tags(inQuery: "I'm exhausted and need something mellow").contains("mellow"))
        #expect(LocalKnowledgeAI.tags(inQuery: "terrifying dark star").contains("dark"))
        #expect(LocalKnowledgeAI.tags(inQuery: "best road trip show").contains("high-energy"))
    }

    @Test func parsesSongMentions() async throws {
        let filters = try await ai.parseSearchIntent("most underrated Scarlet Begonias")
        #expect(filters.songText?.lowercased().contains("scarlet") == true)
    }

    @Test func recommendationPicksFromCandidatesOnly() async throws {
        let rec = try await ai.recommend(query: "something joyful", profile: .empty, candidates: MockData.shows)
        #expect(MockData.shows.contains { $0.identifier == rec.chosenIdentifier })
        #expect(!rec.narrative.isEmpty)
        #expect(rec.narrative.count > 80)
    }

    @Test func showGuideGroundsInSetlist() async throws {
        let guide = try await ai.showGuide(for: MockData.cornellDetail, show: MockData.cornell)
        #expect((1...5).contains(guide.improvisationRating))
        #expect(!guide.musicalHighlights.isEmpty)
        #expect(!guide.fanConsensus.isEmpty)
        // Scarlet > Fire are adjacent segue partners in the mock setlist.
        #expect(guide.bestTransitions.contains { $0.contains("Scarlet") })
    }

    @Test func chatAnswersSongQuestions() async throws {
        let stream = try await ai.chatReply(
            messages: [ChatTurn(role: .user, text: "What's the best Dark Star?")],
            grounding: .empty
        )
        var reply = ""
        for try await chunk in stream { reply += chunk }
        #expect(reply.contains("Dark Star"))
        #expect(reply.count > 100)
    }

    @Test func chatAnswersEraQuestions() async throws {
        let stream = try await ai.chatReply(
            messages: [ChatTurn(role: .user, text: "What made 1973 special?")],
            grounding: .empty
        )
        var reply = ""
        for try await chunk in stream { reply += chunk }
        #expect(reply.count > 100)
    }
}

// MARK: - Taste engine

struct TasteProfileTests {
    private func event(song: String, show: String, year: Int, venue: String, seconds: Double) -> TasteEngine.EventFacts {
        TasteEngine.EventFacts(songKey: song, showIdentifier: show, showYear: year, venue: venue, seconds: seconds)
    }

    @Test func emptyEventsGiveEmptySnapshot() {
        #expect(TasteEngine.recompute(events: []) == .empty)
    }

    @Test func aggregatesErasSongsAndVenues() {
        let events = [
            event(song: "scarlet begonias", show: "a", year: 1977, venue: "Barton Hall", seconds: 600),
            event(song: "scarlet begonias", show: "a", year: 1977, venue: "Barton Hall", seconds: 300),
            event(song: "dark star", show: "b", year: 1972, venue: "Veneta", seconds: 100),
        ]
        let snapshot = TasteEngine.recompute(events: events)
        #expect(snapshot.showsHeard == 2)
        #expect(snapshot.totalSeconds == 1000)
        #expect(snapshot.topSongKeys.first == "scarlet begonias")
        #expect(snapshot.favoriteVenues.first == "Barton Hall")
        let hiatus = snapshot.eraWeights["hiatus-return"] ?? 0
        let europe = snapshot.eraWeights["europe-wall"] ?? 0
        #expect(hiatus > europe)
        #expect(abs(hiatus + europe - 1.0) < 0.001)
    }

    @Test func eraMappingMatchesBoundaries() {
        #expect(TasteEngine.eraID(forYear: 1967) == "primal")
        #expect(TasteEngine.eraID(forYear: 1970) == "anthem")
        #expect(TasteEngine.eraID(forYear: 1972) == "europe-wall")
        #expect(TasteEngine.eraID(forYear: 1977) == "hiatus-return")
        #expect(TasteEngine.eraID(forYear: 1979) == "transition")
        #expect(TasteEngine.eraID(forYear: 1985) == "brent")
        #expect(TasteEngine.eraID(forYear: 1994) == "vince")
    }
}

// MARK: - Player queue

struct PlayerQueueTests {
    @Test func playSetsQueueAndIndex() {
        let engine = PlayerEngine(streaming: MockStreamingProvider())
        engine.play(show: MockData.cornell, tracks: MockData.cornellTracks, startAt: 2)
        #expect(engine.queue.count == MockData.cornellTracks.count)
        #expect(engine.currentIndex == 2)
        #expect(engine.currentTrack?.title == "El Paso")
        #expect(engine.hasContent)
    }

    @Test func jumpAndBoundsAreSafe() {
        let engine = PlayerEngine(streaming: MockStreamingProvider())
        engine.play(show: MockData.cornell, tracks: MockData.cornellTracks, startAt: 99)
        #expect(engine.currentIndex == MockData.cornellTracks.count - 1)
        engine.jump(to: -3)   // ignored
        #expect(engine.currentIndex == MockData.cornellTracks.count - 1)
        engine.jump(to: 0)
        #expect(engine.currentTrack?.trackNumber == 1)
    }

    @Test func emptyTracksFailGracefully() {
        let engine = PlayerEngine(streaming: MockStreamingProvider())
        engine.play(show: MockData.cornell, tracks: [])
        if case .failed = engine.state {} else {
            Issue.record("expected failed state for empty queue")
        }
        #expect(!engine.hasContent)
    }

    @Test func stopClearsEverything() {
        let engine = PlayerEngine(streaming: MockStreamingProvider())
        engine.play(show: MockData.cornell, tracks: MockData.cornellTracks)
        engine.stop()
        #expect(engine.queue.isEmpty)
        #expect(engine.currentShow == nil)
        #expect(engine.state == .idle)
    }
}

// MARK: - Journeys

struct JourneyProgressionTests {
    @Test func progressionUnlocksAndFinishes() {
        let container = ModelContainerFactory.make(inMemory: true)
        let store = JourneyStore(container: container)

        #expect(store.state(for: "gateway") == nil)
        store.start(journeyID: "gateway")
        #expect(store.state(for: "gateway") != nil)

        store.completeDay(journeyID: "gateway", dayIndex: 0, totalDays: 3)
        #expect(store.state(for: "gateway")?.completedDayIndices == [0])
        #expect(store.state(for: "gateway")?.currentDayIndex == 1)

        store.completeDay(journeyID: "gateway", dayIndex: 1, totalDays: 3)
        store.completeDay(journeyID: "gateway", dayIndex: 2, totalDays: 3)
        #expect(store.state(for: "gateway")?.completedAt != nil)
    }

    @Test func completingSameDayTwiceIsIdempotent() {
        let container = ModelContainerFactory.make(inMemory: true)
        let store = JourneyStore(container: container)
        store.start(journeyID: "may-77")
        store.completeDay(journeyID: "may-77", dayIndex: 0, totalDays: 5)
        store.completeDay(journeyID: "may-77", dayIndex: 0, totalDays: 5)
        #expect(store.state(for: "may-77")?.completedDayIndices == [0])
    }
}

// MARK: - Helpers

extension Bundle {
    /// From a test bundle, reach the host app's bundle (where KB resources live).
    var appMainBundle: Bundle {
        // Test bundle lives at ....app/PlugIns/ShakedownAITests.xctest
        let appURL = bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: appURL) ?? .main
    }
}
