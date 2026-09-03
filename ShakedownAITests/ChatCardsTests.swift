import Foundation
import SwiftData
import Testing
@testable import ShakedownAI

/// A chat brain that says exactly what the test tells it to.
private final class ScriptedChatAI: AIProvider {
    let name = "Scripted"
    let reply: String
    private let fallback = MockAIProvider()

    init(reply: String) { self.reply = reply }

    func chatReply(messages: [ChatTurn], grounding: GroundingContext) async throws -> AsyncThrowingStream<String, any Error> {
        let reply = reply
        return AsyncThrowingStream { continuation in
            continuation.yield(reply)
            continuation.finish()
        }
    }

    func recommend(query: String?, profile: TasteSnapshot, candidates: [Show]) async throws -> Recommendation {
        try await fallback.recommend(query: query, profile: profile, candidates: candidates)
    }
    func showGuide(for detail: RecordingDetail, show: Show?) async throws -> ShowGuide {
        try await fallback.showGuide(for: detail, show: show)
    }
    func parseSearchIntent(_ text: String) async throws -> SearchFilters {
        try await fallback.parseSearchIntent(text)
    }
    func curateCollection(brief: CollectionBrief, candidates: [CollectionCandidate]) async throws -> CuratedCollection {
        try await fallback.curateCollection(brief: brief, candidates: candidates)
    }
}

private func makeEnvironment(ai: any AIProvider, recording: MockRecordingProvider = MockRecordingProvider()) -> AppEnvironment {
    let container = ModelContainerFactory.make(inMemory: true)
    return AppEnvironment(
        modelContainer: container,
        downloads: DownloadManager(container: container,
                                   makeSession: { _ in URLSession(configuration: .ephemeral) }),
        recordingProvider: recording,
        metadataProvider: recording,
        streamingProvider: MockStreamingProvider(),
        aiProvider: ai,
        authProvider: MockAuthProvider()
    )
}

struct ChatCardsTests {

    @Test func replyWithShowTokenAttachesAPlayableCard() async {
        let env = makeEnvironment(ai: ScriptedChatAI(reply: "Try \(ChatLink.show("1977-05-08", label: "Cornell")) tonight."))
        let model = ChatModel(env: env)
        await model.ask("Where do I start?")

        let reply = model.messages.last
        #expect(reply?.role == .assistant)
        #expect(reply?.shows.map(\.identifier) == [MockData.cornell.identifier])
        #expect(reply?.text.contains("▶\u{FE0E} Cornell") == true)
    }

    @Test func cardsSurviveReload() async {
        let env = makeEnvironment(ai: ScriptedChatAI(reply: "Go \(ChatLink.show("1977-05-08", label: "Cornell"))."))
        await ChatModel(env: env).ask("Where do I start?")

        let reloaded = ChatModel(env: env)
        #expect(reloaded.messages.count == 2)
        #expect(reloaded.messages.last?.shows.map(\.identifier) == [MockData.cornell.identifier])
        #expect(reloaded.messages.first?.shows.isEmpty == true)
    }

    @Test func missingTapeGetsNoCard() async {
        let recording = MockRecordingProvider()
        recording.showsResult = []
        let env = makeEnvironment(ai: ScriptedChatAI(reply: "Maybe \(ChatLink.show("1971-13-99", label: "Phantom"))."),
                                  recording: recording)
        let model = ChatModel(env: env)
        await model.ask("Anything from a night that never happened?")

        #expect(model.messages.last?.shows.isEmpty == true)
        #expect(model.messages.last?.text.contains("(no tape in the archive for this one)") == true)
    }

    @Test func looselyDatedTokensStillResolve() async {
        let env = makeEnvironment(ai: ScriptedChatAI(reply: "Hear \(ChatLink.show("5/8/77", label: "Cornell"))."))
        let model = ChatModel(env: env)
        await model.ask("Cornell?")

        #expect(model.messages.last?.shows.map(\.identifier) == [MockData.cornell.identifier])
        #expect(model.messages.last?.text.contains("[[show:1977-05-08|") == true)
    }

    @Test func messageRecordRoundTripsShows() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        let record = ChatMessageRecord(role: "assistant", text: "x")
        context.insert(record)
        #expect(record.shows.isEmpty)
        #expect(record.showsData == nil)

        record.shows = [MockData.cornell, MockData.veneta]
        try context.save()
        #expect(record.shows == [MockData.cornell, MockData.veneta])

        record.shows = []
        #expect(record.showsData == nil)
    }

    @Test func searchToolCollapsesTapesToNights() {
        var audience = MockData.cornell
        audience.identifier = "gd77-05-08.aud.other"
        audience.avgRating = 3.0
        let nights = OpenAIResponsesAI.bestTapePerNight([audience, MockData.veneta, MockData.cornell])
        #expect(nights.map(\.dateString) == ["1977-05-08", "1972-08-27"] || nights.map(\.dateString) == ["1972-08-27", "1977-05-08"])
        #expect(nights.count == 2)
        #expect(nights.contains { $0.identifier == MockData.cornell.identifier })
        #expect(!nights.contains { $0.identifier == audience.identifier })
    }
}
