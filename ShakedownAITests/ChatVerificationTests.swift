import Foundation
import Testing
@testable import ShakedownAI

struct ChatVerificationTests {

    @Test func extractsUniqueShowDates() {
        let text = """
        Try \(ChatLink.show("1977-05-08", label: "Cornell")) then \
        \(ChatLink.show("1972-08-27", label: "Veneta")) and again \
        \(ChatLink.show("1977-05-08", label: "Cornell repeat")) plus \
        \(ChatLink.song("ripple", label: "Ripple")).
        """
        #expect(ChatLink.showDates(in: text) == ["1977-05-08", "1972-08-27"])
    }

    @Test func availableShowsGetPlayMarker() {
        let text = "Hear \(ChatLink.show("1977-05-08", label: "Cornell 5/8/77")) tonight."
        let verified = ChatLink.verifyShowTokens(text, availability: ["1977-05-08": true])
        #expect(verified.contains("[[show:1977-05-08|▶\u{FE0E} Cornell 5/8/77]]"))
    }

    @Test func unavailableShowsLoseTheLink() {
        let text = "Maybe \(ChatLink.show("1971-13-99", label: "Phantom Night"))."
        let verified = ChatLink.verifyShowTokens(text, availability: ["1971-13-99": false])
        #expect(!verified.contains("[[show:"))
        #expect(verified.contains("Phantom Night (no tape in the archive for this one)"))
    }

    @Test func unverifiedShowsAreLeftUntouched() {
        // Network failure → no entry in the map → keep the link rather than
        // wrongly declaring the show missing.
        let text = "See \(ChatLink.show("1973-06-10", label: "RFK"))."
        let verified = ChatLink.verifyShowTokens(text, availability: [:])
        #expect(verified == text)
    }

    @Test func songAndEraTokensAreNeverTouched() {
        let text = "\(ChatLink.song("dark star", label: "Dark Star")) in \(ChatLink.era("anthem", label: "the Anthem years"))."
        let verified = ChatLink.verifyShowTokens(text, availability: [:])
        #expect(verified == text)
    }

    @Test func markerIsNotDoubledOnReverification() {
        let once = ChatLink.verifyShowTokens(
            "Go \(ChatLink.show("1977-05-08", label: "Cornell"))",
            availability: ["1977-05-08": true]
        )
        let twice = ChatLink.verifyShowTokens(once, availability: ["1977-05-08": true])
        #expect(twice == once)
        let markerCount = twice.unicodeScalars.filter { $0 == "▶" }.count
        #expect(markerCount == 1)
    }
}
