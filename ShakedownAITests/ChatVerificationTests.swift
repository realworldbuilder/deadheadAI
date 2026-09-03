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

// MARK: - Cards

struct ChatShowVerificationTests {

    private var cornell: Show { MockData.cornell }
    private var veneta: Show { MockData.veneta }
    private var fillmore: Show { MockData.fillmore70 }

    @Test func attachesBestTapeInOrderOfFirstMentionDedupedAndCapped() {
        let text = """
        Go \(ChatLink.show("1977-05-08", label: "Cornell")), \
        \(ChatLink.show("1972-08-27", label: "Veneta")), \
        \(ChatLink.show("1977-05-08", label: "Cornell again")), then \
        \(ChatLink.show("1970-02-13", label: "Fillmore")).
        """
        var second = cornell
        second.identifier = "gd77-05-08.aud.second"
        let lookups: [String: [Show]] = [
            "1977-05-08": [cornell, second],
            "1972-08-27": [veneta],
            "1970-02-13": [fillmore],
        ]
        let verified = ChatLink.verifyShows(in: text, lookups: lookups, maxAttachments: 2)
        #expect(verified.shows.map(\.identifier) == [cornell.identifier, veneta.identifier])
        #expect(verified.text.contains("[[show:1977-05-08|▶\u{FE0E} Cornell]]"))
        #expect(verified.text.contains("[[show:1970-02-13|▶\u{FE0E} Fillmore]]"))
    }

    @Test func failedLookupKeepsLinkAndSkipsCard() {
        let text = "See \(ChatLink.show("1973-06-10", label: "RFK"))."
        let verified = ChatLink.verifyShows(in: text, lookups: [:])
        #expect(verified.text == text)
        #expect(verified.shows.isEmpty)
    }

    @Test func emptyLookupDropsLinkAndCard() {
        let text = "Maybe \(ChatLink.show("1971-13-99", label: "Phantom Night"))."
        let verified = ChatLink.verifyShows(in: text, lookups: ["1971-13-99": []])
        #expect(verified.shows.isEmpty)
        #expect(!verified.text.contains("[[show:"))
        #expect(verified.text.contains("Phantom Night (no tape in the archive for this one)"))
    }

    @Test func normalizesLooseDatesInShowTokens() {
        #expect(ChatLink.normalizingShowDates("[[show:5/8/77|Cornell]]") == "[[show:1977-05-08|Cornell]]")
        #expect(ChatLink.normalizingShowDates("[[show:1977-5-8|Cornell]]") == "[[show:1977-05-08|Cornell]]")
        #expect(ChatLink.normalizingShowDates("[[show: 1977-05-08 |Cornell]]") == "[[show:1977-05-08|Cornell]]")
        let iso = "[[show:1977-05-08|Cornell]] and [[song:dark star|Dark Star]]"
        #expect(ChatLink.normalizingShowDates(iso) == iso)
        let junk = "[[show:someday|Cornell]]"
        #expect(ChatLink.normalizingShowDates(junk) == junk)
    }

    @Test func isoDatesParsesEveryCommonSpelling() {
        #expect(ChatLink.isoDates(in: "5/8/77 then 1977-05-08 and 8-27-72") == ["1972-08-27", "1977-05-08"])
        #expect(ChatLink.isoDates(in: "12/25/2010").isEmpty)
    }
}

// MARK: - Inline segments

struct ChatSegmentTests {

    @Test func cardsInterleaveWithProseAndCarryTheirNote() {
        let text = """
        1973 was huge. Start here:

        [[show:1973-06-22|▶︎ PNE 6/22/73]] — a high-energy show with a wild Dark Star.
        [[show:1973-12-18|▶︎ Tampa 12/18/73]]: an epic Eyes of the World.

        Enjoy the treasures!
        """
        let segments = ChatLink.segments(in: text, cardDates: ["1973-06-22", "1973-12-18"])
        #expect(segments == [
            .text("1973 was huge. Start here:"),
            .show(date: "1973-06-22", note: "a high-energy show with a wild Dark Star."),
            .show(date: "1973-12-18", note: "an epic Eyes of the World."),
            .text("Enjoy the treasures!"),
        ])
    }

    @Test func tokensWithoutCardsStayInTheProse() {
        let text = "Hear [[show:1977-05-08|Cornell]] and [[song:dark star|Dark Star]] then [[show:1972-08-27|Veneta]]."
        let segments = ChatLink.segments(in: text, cardDates: ["1972-08-27"])
        #expect(segments == [
            .text("Hear [[show:1977-05-08|Cornell]] and [[song:dark star|Dark Star]] then"),
            .show(date: "1972-08-27", note: nil),
        ])
    }

    @Test func midSentenceTokensBecomeCardsWithoutStealingTheProse() {
        let text = "Make it [[show:1977-05-08|Cornell]]: the Dew levels the room. Then [[show:1970-02-13|Fillmore]] (hidden gem)."
        let segments = ChatLink.segments(in: text, cardDates: ["1977-05-08", "1970-02-13"])
        #expect(segments == [
            .text("Make it"),
            .show(date: "1977-05-08", note: nil),
            .text("the Dew levels the room. Then"),
            .show(date: "1970-02-13", note: nil),
            .text("(hidden gem)."),
        ])
    }

    @Test func midLineTokenKeepsAShortAsideAsItsNote() {
        let text = "Check out the show here: [[show:1977-05-08|Cornell]] — a true landmark moment!"
        let segments = ChatLink.segments(in: text, cardDates: ["1977-05-08"])
        #expect(segments == [
            .text("Check out the show here:"),
            .show(date: "1977-05-08", note: "a true landmark moment!"),
        ])
    }

    @Test func midLineTokenLeavesALongTailAsProse() {
        let tail = String(repeating: "the Dew builds and builds until the room levels. ", count: 5)
        let text = "You can't beat [[show:1977-05-08|Cornell]] — \(tail)"
        let segments = ChatLink.segments(in: text, cardDates: ["1977-05-08"])
        #expect(segments == [
            .text("You can't beat"),
            .show(date: "1977-05-08", note: nil),
            .text(tail.trimmingCharacters(in: .whitespaces)),
        ])
    }

    @Test func lineMentioningAnotherShowIsProseNotANote() {
        let text = "[[show:1977-05-08|Cornell]] — see also [[show:1970-02-13|Fillmore]]\nDone."
        let segments = ChatLink.segments(in: text, cardDates: ["1977-05-08", "1970-02-13"])
        #expect(segments == [
            .show(date: "1977-05-08", note: nil),
            .text("see also"),
            .show(date: "1970-02-13", note: nil),
            .text("Done."),
        ])
    }

    @Test func offlineSongAnswerSplitsIntoCardsWithNotes() async throws {
        let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)
        let ai = LocalKnowledgeAI(knowledgeBase: kb)
        let stream = try await ai.chatReply(
            messages: [ChatTurn(role: .user, text: "Pick one show with the best morning dew")],
            grounding: .empty
        )
        var reply = ""
        for try await chunk in stream { reply += chunk }

        let dates = ChatLink.showDates(in: reply)
        let lookups = Dictionary(uniqueKeysWithValues: dates.map { ($0, [MockData.cornell]) })
        let verified = ChatLink.verifyShows(in: reply, lookups: lookups, maxAttachments: 10)
        let segments = ChatLink.segments(in: verified.text, cardDates: Set(dates))

        let cards = segments.compactMap { segment -> (String, String?)? in
            if case .show(let date, let note) = segment { return (date, note) }
            return nil
        }
        #expect(cards.count == dates.count)
        #expect(cards.allSatisfy { $0.1 != nil })
        #expect(cards.allSatisfy { !($0.1 ?? "").contains("[[") })
        for case .text(let text) in segments {
            #expect(!text.contains("[[show:"))
        }
    }

    @Test func repeatedDateGetsOneCardThenLinks() {
        let text = "[[show:1977-05-08|Cornell]] is the one. Yes, [[show:1977-05-08|Cornell]] again."
        let segments = ChatLink.segments(in: text, cardDates: ["1977-05-08"])
        #expect(segments == [
            .show(date: "1977-05-08", note: nil),
            .text("is the one. Yes, [[show:1977-05-08|Cornell]] again."),
        ])
    }

    @Test func noteStopsAtTheLineBreak() {
        let text = "[[show:1977-05-08|Cornell]] - the Betty board.\nNext paragraph."
        let segments = ChatLink.segments(in: text, cardDates: ["1977-05-08"])
        #expect(segments == [
            .show(date: "1977-05-08", note: "the Betty board."),
            .text("Next paragraph."),
        ])
    }

    @Test func plainTextHasNoCards() {
        #expect(ChatLink.segments(in: "Just chatting.", cardDates: []) == [.text("Just chatting.")])
    }
}
