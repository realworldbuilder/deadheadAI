import Foundation
import SwiftUI
import Testing
@testable import ShakedownAI

struct ChatLinkTests {

    @Test func rendersTokensAsLinks() {
        let text = "Start with \(ChatLink.show("1977-05-08", label: "Cornell 5/8/77")) tonight."
        let rendered = ChatLink.render(text, linkColor: .red)
        let plain = String(rendered.characters)
        #expect(plain == "Start with Cornell 5/8/77 tonight.")

        let links = rendered.runs.compactMap(\.link)
        #expect(links.count == 1)
        #expect(ChatLink.destination(for: links[0]) == .show(date: "1977-05-08"))
    }

    @Test func roundTripsAllKinds() throws {
        let showURL = try #require(ChatLink.url(kind: "show", value: "1972-08-27"))
        #expect(ChatLink.destination(for: showURL) == .show(date: "1972-08-27"))

        let songURL = try #require(ChatLink.url(kind: "song", value: "dark star"))
        #expect(ChatLink.destination(for: songURL) == .song(key: "dark star"))

        let eraURL = try #require(ChatLink.url(kind: "era", value: "brent"))
        #expect(ChatLink.destination(for: eraURL) == .era(id: "brent"))

        let webURL = try #require(URL(string: "https://example.com"))
        #expect(ChatLink.destination(for: webURL) == nil)
    }

    @Test func handlesMultipleAndMalformedTokens() {
        let text = "\(ChatLink.song("ripple", label: "Ripple")) then \(ChatLink.era("primal", label: "Primal Dead")) and [[broken"
        let rendered = ChatLink.render(text, linkColor: .red)
        #expect(String(rendered.characters) == "Ripple then Primal Dead and [[broken")
        #expect(rendered.runs.compactMap(\.link).count == 2)
    }

    @Test func plainTextStripsTokens() {
        let text = "Hear \(ChatLink.show("1977-05-08", label: "Cornell")) soon."
        #expect(ChatLink.plainText(text) == "Hear Cornell soon.")
    }

    @Test func localAIEmitsLinksInSongAnswers() async throws {
        let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)
        let ai = LocalKnowledgeAI(knowledgeBase: kb)
        let stream = try await ai.chatReply(
            messages: [ChatTurn(role: .user, text: "What's the best Dark Star?")],
            grounding: .empty
        )
        var reply = ""
        for try await chunk in stream { reply += chunk }
        #expect(reply.contains("[[song:dark star|"))
        #expect(reply.contains("[[show:"))
        // Every emitted token parses into a link.
        let rendered = ChatLink.render(reply, linkColor: .red)
        #expect(!rendered.runs.compactMap(\.link).isEmpty)
        #expect(!String(rendered.characters).contains("[["))
    }

    @Test func localAIEmitsLinksInMoodAnswers() async throws {
        let kb = KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle)
        let ai = LocalKnowledgeAI(knowledgeBase: kb)
        let stream = try await ai.chatReply(
            messages: [ChatTurn(role: .user, text: "I need something mellow tonight")],
            grounding: .empty
        )
        var reply = ""
        for try await chunk in stream { reply += chunk }
        #expect(reply.contains("[[show:"))
    }
}
