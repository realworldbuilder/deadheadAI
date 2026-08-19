import Foundation
import Testing
@testable import ShakedownAI

/// The on-device model is small enough to answer out of range or to type "none"
/// into a field it should have left empty. These guards keep a sloppy answer
/// from crashing an array subscript or leaking junk into a search.
struct OnDeviceAnswerTests {

    // MARK: - Candidate numbering

    @Test func picksTheShowTheModelNumbered() {
        #expect(OnDeviceAnswer.clampIndex(1, count: 8) == 0)
        #expect(OnDeviceAnswer.clampIndex(5, count: 8) == 4)
        #expect(OnDeviceAnswer.clampIndex(8, count: 8) == 7)
    }

    @Test func anOutOfRangeNumberLandsInsideTheList() {
        #expect(OnDeviceAnswer.clampIndex(99, count: 8) == 7)
        #expect(OnDeviceAnswer.clampIndex(0, count: 8) == 0)
        #expect(OnDeviceAnswer.clampIndex(-3, count: 8) == 0)
    }

    @Test func anEmptyCandidateListNeverIndexesPastZero() {
        #expect(OnDeviceAnswer.clampIndex(4, count: 0) == 0)
    }

    // MARK: - Empty optionals

    @Test func realAnswersSurvive() {
        #expect(OnDeviceAnswer.nilIfBlank("Winterland") == "Winterland")
        #expect(OnDeviceAnswer.nilIfBlank("  Dark Star  ") == "Dark Star")
    }

    @Test func theModelsWaysOfSayingNothingAllBecomeNil() {
        #expect(OnDeviceAnswer.nilIfBlank(nil) == nil)
        #expect(OnDeviceAnswer.nilIfBlank("") == nil)
        #expect(OnDeviceAnswer.nilIfBlank("   ") == nil)
        #expect(OnDeviceAnswer.nilIfBlank("none") == nil)
        #expect(OnDeviceAnswer.nilIfBlank("None") == nil)
        #expect(OnDeviceAnswer.nilIfBlank("  NONE  ") == nil)
    }

    // MARK: - Streaming placeholders

    @Test func theStreamsPreTokenPlaceholderIsNotShownToTheListener() {
        #expect(OnDeviceAnswer.isPlaceholder("null"))
        #expect(OnDeviceAnswer.isPlaceholder(""))
        #expect(OnDeviceAnswer.isPlaceholder("  "))
    }

    @Test func realProseIsNeverMistakenForAPlaceholder() {
        #expect(!OnDeviceAnswer.isPlaceholder("Dark Star opens the second set"))
        #expect(!OnDeviceAnswer.isPlaceholder("nullify"))
    }

    // MARK: - Song grounding

    private let cornellSongs: Set<String> = ["scarlet begonias", "morning dew", "fire on the mountain"]

    @Test func realSongsPassThrough() {
        let lines = ["Scarlet Begonias into Fire on the Mountain", "The Morning Dew finale"]
        #expect(OnDeviceAnswer.grounded(lines, in: cornellSongs, fallback: []) == lines)
    }

    @Test func inventedSongsAreDropped() {
        let lines = ["Scarlet Begonias", "Carefree/Comin' Back to Earth", "Mickey, Duck"]
        #expect(OnDeviceAnswer.grounded(lines, in: cornellSongs, fallback: []) == ["Scarlet Begonias"])
    }

    @Test func anAllInventedListFallsBackToCuratedSongs() {
        let lines = ["Mickey, Duck", "Carefree/Comin' Back to Earth"]
        let fallback = ["Scarlet Begonias", "Morning Dew", "Fire on the Mountain", "Estimated Prophet"]
        #expect(OnDeviceAnswer.grounded(lines, in: cornellSongs, fallback: fallback)
                == ["Scarlet Begonias", "Morning Dew", "Fire on the Mountain"])
    }

    @Test func withNoVocabularyToCheckAgainstNothingIsDropped() {
        let lines = ["some moment", "another moment"]
        #expect(OnDeviceAnswer.grounded(lines, in: [], fallback: []) == lines)
    }

    @Test func anAllInventedListWithNoFallbackKeepsWhatTheModelSaid() {
        let lines = ["Mickey, Duck"]
        #expect(OnDeviceAnswer.grounded(lines, in: cornellSongs, fallback: []) == lines)
    }
}
