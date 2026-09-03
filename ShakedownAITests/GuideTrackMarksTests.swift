import Foundation
import Testing
@testable import ShakedownAI

// MARK: - Grounding guide prose against the tape's tracks

struct GuideTrackMarksTests {
    private func tracks(_ titles: [String]) -> [Track] {
        titles.enumerated().map { index, title in
            Track(fileName: "t\(index).mp3", title: title, trackNumber: index + 1, durationSeconds: 300)
        }
    }

    private func guide(highlights: [String] = [], transitions: [String] = [],
                       listenFor: [String] = [], recommended: [String] = []) -> ShowGuide {
        ShowGuide(overallMood: "", historicalContext: "", musicalHighlights: highlights,
                  bestTransitions: transitions, improvisationRating: 3, accessibility: "",
                  recordingNotes: "", listenFor: listenFor, fanConsensus: "",
                  recommendedTracks: recommended)
    }

    private let aliases = [
        "half step": "mississippi half step uptown toodeloo",
        "mississippi half step": "mississippi half step uptown toodeloo",
        "franklin's": "franklin's tower",
        "scarlet": "scarlet begonias",
        "fire": "fire on the mountain",
        "eyes": "eyes of the world",
    ]

    private let cornell = ["New Minglewood Blues", "Loser", "Scarlet Begonias",
                           "Fire On The Mountain", "Estimated Prophet", "Morning Dew"]

    @Test func highlightProseMarksAliasedSongs() {
        let tape = tracks(["Mississippi Half-Step Uptown Toodeloo", "Franklin's Tower", "Loser"])
        let line = "Impressive guitar work from Jerry during Half Step > Franklin's Tower"
        let marks = GuideTrackMarks.marks(for: guide(highlights: [line]), tracks: tape, aliases: aliases)
        #expect(marks == [0: .highlight, 1: .highlight])
    }

    @Test func transitionLineMarksBothEndsAndIgnoresTheTail() {
        let tape = tracks(cornell)
        let line = "Scarlet Begonias > Fire on the Mountain — Celebrated, unlike the Morning Dew"
        let marks = GuideTrackMarks.marks(for: guide(transitions: [line]), tracks: tape, aliases: aliases)
        #expect(marks == [2: .transition, 3: .transition])
    }

    @Test func shortAliasesOnlyCountAsArrowChainSegments() {
        let tape = tracks(cornell)
        #expect(GuideTrackMarks.trackIndices(named: "Scarlet > Fire", tracks: tape, aliases: aliases) == [2, 3])
        #expect(GuideTrackMarks.trackIndices(named: "The fire in Jerry's playing all night",
                                             tracks: tape, aliases: aliases).isEmpty)
    }

    @Test func fragmentsNeverAnchor() {
        let tape = tracks(["Dark Star", "Morning Dew"])
        #expect(GuideTrackMarks.trackIndices(named: "Star", tracks: tape, aliases: [:]).isEmpty)
        #expect(GuideTrackMarks.trackIndices(named: "A patient Dark Star", tracks: tape, aliases: [:]) == [0])
    }

    @Test func combinedFileMatchesEitherSong() {
        let tape = tracks(["Loser", "Scarlet Begonias > Fire On The Mountain", "Estimated Prophet"])
        #expect(GuideTrackMarks.trackIndices(named: "Scarlet Begonias > Fire on the Mountain",
                                             tracks: tape, aliases: aliases) == [1])
        #expect(GuideTrackMarks.trackIndices(named: "Scarlet > Fire", tracks: tape, aliases: aliases) == [1])
        #expect(GuideTrackMarks.trackIndices(named: "A blistering Fire on the Mountain",
                                             tracks: tape, aliases: aliases) == [1])
    }

    @Test func repeatedSongMarksEveryOccurrence() {
        let tape = tracks(["Playing in the Band", "Drums", "Playing in the Band"])
        let marks = GuideTrackMarks.marks(for: guide(listenFor: ["The Playing in the Band reprise"]),
                                          tracks: tape, aliases: [:])
        #expect(marks == [0: .listenFor, 2: .listenFor])
    }

    @Test func categoriesUnionOnOneTrack() {
        let tape = tracks(cornell)
        let g = guide(highlights: ["Morning Dew"], transitions: ["Scarlet > Fire — the reference version"],
                      listenFor: ["Jerry's Morning Dew solo"], recommended: ["Estimated Prophet"])
        let marks = GuideTrackMarks.marks(for: g, tracks: tape, aliases: aliases)
        #expect(marks[5] == [.highlight, .listenFor])
        #expect(marks[2] == .transition)
        #expect(marks[3] == .transition)
        #expect(marks[4] == .highlight)
        #expect(marks[0] == nil)
    }

    @Test func quotedSongNamesStillMatch() {
        let tape = tracks(["Truckin'", "Estimated Prophet", "Franklin's Tower"])
        let line = "Phil's bass lines, especially evident in 'Estimated Prophet' and 'Franklin's Tower'."
        #expect(GuideTrackMarks.trackIndices(named: line, tracks: tape, aliases: aliases) == [1, 2])
        #expect(GuideTrackMarks.trackIndices(named: "A raging 'Truckin''", tracks: tape, aliases: [:]) == [0])
    }

    @Test func emptyInputsMarkNothing() {
        #expect(GuideTrackMarks.marks(for: guide(), tracks: tracks(cornell), aliases: aliases).isEmpty)
        #expect(GuideTrackMarks.marks(for: guide(highlights: ["Morning Dew"]), tracks: [], aliases: aliases).isEmpty)
    }
}
