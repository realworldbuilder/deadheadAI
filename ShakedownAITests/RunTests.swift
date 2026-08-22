import Foundation
import Testing
@testable import ShakedownAI

// MARK: - Famous runs: knowledge integrity

struct FamousRunKnowledgeTests {
    private let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)

    @Test func runsLoadAndAreWellFormed() {
        #expect(kb.runs.count >= 10)
        #expect(Set(kb.runs.map(\.id)).count == kb.runs.count, "run ids must be unique")
        let eraIDs = Set(kb.eras.map(\.id))
        for run in kb.runs {
            #expect(IADates.parse(run.date) != nil, "\(run.id): bad date \(run.date)")
            #expect(!run.title.isEmpty)
            #expect(!run.blurb.isEmpty)
            #expect(!run.songKeys.isEmpty)
            if let era = run.eraID {
                #expect(eraIDs.contains(era), "\(run.id) has unknown era \(era)")
            }
        }
    }

    @Test func runSongKeysArePreNormalized() {
        for run in kb.runs {
            for key in run.songKeys {
                #expect(key == Track.normalizeSongKey(key),
                        "\(run.id): songKey \"\(key)\" is not normalized")
            }
        }
    }

    @Test func everyRunDateHasANotableShow() {
        for run in kb.runs {
            #expect(kb.notableShow(on: run.date) != nil,
                    "\(run.id) anchors to \(run.date), which is not in notable_shows")
        }
    }

    @Test func runLookupsWork() {
        let wembley = kb.runs(on: "1972-04-08")
        #expect(wembley.contains { $0.songKeys == ["truckin'", "caution"] })
        #expect(!kb.runs(containing: "dark star").isEmpty)
        #expect(kb.run(id: "1977-05-08-scarlet-fire") != nil)
    }
}

// MARK: - Run resolution against real track lists

struct RunResolverTests {
    private func tracks(_ titles: [String]) -> [Track] {
        titles.enumerated().map { index, title in
            Track(fileName: "t\(index).mp3", title: title, trackNumber: index + 1, durationSeconds: 300)
        }
    }

    private func run(_ keys: [String]) -> FamousRun {
        FamousRun(id: "test", date: "1972-04-08", title: "Test", songKeys: keys, blurb: "b", eraID: nil, tags: [])
    }

    @Test func exactContiguousSequenceResolves() {
        let list = tracks(["Bertha", "Truckin'", "Caution (Do Not Stop On Tracks)", "One More Saturday Night"])
        #expect(RunResolver.resolve(run(["truckin'", "caution"]), in: list) == 1...2)
    }

    @Test func singleBridgingTrackIsTolerated() {
        let list = tracks(["Dark Star", "Drums", "The Other One"])
        #expect(RunResolver.resolve(run(["dark star", "the other one"]), in: list) == 0...2)
    }

    @Test func twoInterveningTracksRejectTheRun() {
        let list = tracks(["Dark Star", "Drums", "Space", "The Other One"])
        #expect(RunResolver.resolve(run(["dark star", "the other one"]), in: list) == nil)
    }

    @Test func combinedTitleTrackSatisfiesConsecutiveKeys() {
        let list = tracks(["Bertha", "Truckin' > Caution", "One More Saturday Night"])
        #expect(RunResolver.resolve(run(["truckin'", "caution"]), in: list) == 1...1)
    }

    @Test func missingSongMeansNoResolution() {
        let list = tracks(["Bertha", "Truckin'", "One More Saturday Night"])
        #expect(RunResolver.resolve(run(["truckin'", "caution"]), in: list) == nil)
    }

    @Test func outOfOrderSongsMeanNoResolution() {
        let list = tracks(["Caution (Do Not Stop On Tracks)", "Bertha", "Truckin'"])
        #expect(RunResolver.resolve(run(["truckin'", "caution"]), in: list) == nil)
    }

    @Test func repeatedSongAnchorsOnTheOccurrenceThatCompletesTheRun() {
        // Dark Star opens set one, but the famous run lives in set two.
        let list = tracks(["Dark Star", "Casey Jones", "Sugaree",
                           "Dark Star", "St. Stephen", "The Eleven"])
        #expect(RunResolver.resolve(run(["dark star", "st stephen", "the eleven"]), in: list) == 3...5)
    }

    @Test func extendedTitlesStillMatchWholeWords() {
        let list = tracks(["Truckin'", "Caution Jam"])
        #expect(RunResolver.resolve(run(["truckin'", "caution"]), in: list) == 0...1)
        // But fragments never anchor: "star" alone must not match "Dark Star".
        let fragments = tracks(["Dark Star"])
        #expect(RunResolver.resolve(run(["star spangled banner"]), in: fragments) == nil)
    }

    @Test func singleSongRunResolves() {
        let list = tracks(["Casey Jones", "Morning Dew", "One More Saturday Night"])
        #expect(RunResolver.resolve(run(["morning dew"]), in: list) == 1...1)
    }

    @Test func everyJourneyFocusRunResolvesInTheKnowledgeBase() {
        let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)
        for journey in kb.journeys {
            for day in journey.days {
                guard let runID = day.focusRunID else { continue }
                guard let run = kb.run(id: runID) else {
                    Issue.record("\(journey.id) references missing run \(runID)")
                    continue
                }
                #expect(run.date == day.showDate,
                        "\(journey.id): run \(runID) is dated \(run.date), day is \(day.showDate)")
            }
        }
    }

    @Test func cornellScarletFireResolvesFromTheRealKnowledgeBase() {
        let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)
        guard let scarletFire = kb.run(id: "1977-05-08-scarlet-fire") else {
            Issue.record("missing 1977-05-08-scarlet-fire run")
            return
        }
        let cornell = tracks(["New Minglewood Blues", "Loser", "Scarlet Begonias",
                              "Fire On The Mountain", "Estimated Prophet"])
        #expect(RunResolver.resolve(scarletFire, in: cornell) == 2...3)
    }
}

// MARK: - Grounding model-written transition lines

struct TransitionGroundingTests {
    private let tape = [
        Track(fileName: "t1.mp3", title: "Truckin'", trackNumber: 1, durationSeconds: 600),
        Track(fileName: "t2.mp3", title: "Caution (Do Not Stop On Tracks)", trackNumber: 2, durationSeconds: 900),
        Track(fileName: "t3.mp3", title: "One More Saturday Night", trackNumber: 3, durationSeconds: 300),
    ]

    @Test func keepsLinesWhoseSongsAreOnTheTape() {
        let lines = ["Truckin' > Caution — reviewers call it the night's peak"]
        #expect(TransitionGrounding.filter(lines, tracks: tape) == lines)
    }

    @Test func dropsLinesNamingSongsNotOnTheTape() {
        let lines = ["Truckin' > Caution — the real one",
                     "Dark Star > Morning Dew — invented by the model"]
        #expect(TransitionGrounding.filter(lines, tracks: tape).count == 1)
    }

    @Test func dropsEverythingWhenTheTapeIsEmpty() {
        #expect(TransitionGrounding.filter(["Truckin' > Caution"], tracks: []).isEmpty)
    }

    @Test func shortTitlesMatchExtendedTapeTitles() {
        let lines = ["Truckin' > Caution (Do Not Stop On Tracks)"]
        #expect(TransitionGrounding.filter(lines, tracks: tape) == lines)
    }
}

// MARK: - Offline brain surfaces runs

@MainActor
struct OfflineGuideRunTests {
    @Test func guideLeadsTransitionsAndHighlightsWithTheFamousRun() async throws {
        let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)
        let ai = LocalKnowledgeAI(knowledgeBase: kb)
        let detail = RecordingDetail(
            identifier: "gd1972-04-08.sbd.test",
            title: "Wembley Empire Pool",
            dateString: "1972-04-08",
            venue: "Wembley Empire Pool",
            location: "London, England",
            source: "sbd",
            lineage: nil, notes: nil, setlistText: nil,
            tracks: [
                Track(fileName: "t1.mp3", title: "Bertha", trackNumber: 1, durationSeconds: 300),
                Track(fileName: "t2.mp3", title: "Truckin'", trackNumber: 2, durationSeconds: 688),
                Track(fileName: "t3.mp3", title: "Caution (Do Not Stop On Tracks)", trackNumber: 3, durationSeconds: 1028),
                Track(fileName: "t4.mp3", title: "One More Saturday Night", trackNumber: 4, durationSeconds: 292),
            ],
            reviews: []
        )
        let guide = try await ai.showGuide(for: detail, show: nil)
        #expect(guide.bestTransitions.first?.contains("Truckin' > Caution") == true)
        #expect(guide.musicalHighlights.first?.contains("Truckin' > Caution") == true)
    }

    @Test func guideSkipsRunsTheTapeDoesNotContain() async throws {
        let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)
        let ai = LocalKnowledgeAI(knowledgeBase: kb)
        // Same date, but a partial tape missing Caution entirely.
        let detail = RecordingDetail(
            identifier: "gd1972-04-08.aud.partial",
            title: "Wembley Empire Pool",
            dateString: "1972-04-08",
            venue: "Wembley Empire Pool",
            location: "London, England",
            source: "aud",
            lineage: nil, notes: nil, setlistText: nil,
            tracks: [
                Track(fileName: "t1.mp3", title: "Bertha", trackNumber: 1, durationSeconds: 300),
                Track(fileName: "t2.mp3", title: "Truckin'", trackNumber: 2, durationSeconds: 688),
            ],
            reviews: []
        )
        let guide = try await ai.showGuide(for: detail, show: nil)
        #expect(!guide.bestTransitions.contains { $0.contains("Caution") })
    }
}
