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

    @Test func replyWithNoShowsGetsStartHereCardsAndActions() async {
        let env = makeEnvironment(ai: ScriptedChatAI(reply: "Europe '72 was a transformative tour with tighter arrangements."))
        let model = ChatModel(env: env)
        await model.ask("What makes Europe '72 different?")

        let reply = model.messages.last
        #expect(reply?.shows.isEmpty == false)
        #expect(reply?.actions.contains { if case .openEra(let id, _) = $0 { return id == "europe-wall" }; return false } == true)
        #expect(reply?.actions.contains { if case .ask = $0 { return true }; return false } == true)

        let reloaded = ChatModel(env: env)
        #expect(reloaded.messages.last?.actions == reply?.actions)
        #expect(reloaded.messages.last?.shows == reply?.shows)
    }

    @Test func replyWithCardsGetsNoExtras() async {
        let env = makeEnvironment(ai: ScriptedChatAI(reply: "Try \(ChatLink.show("1977-05-08", label: "Cornell")) tonight."))
        let model = ChatModel(env: env)
        await model.ask("Anything from 1977?")
        #expect(model.messages.last?.shows.count == 1)
        #expect(model.messages.last?.actions.isEmpty == true)
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

struct ChatFollowUpPlannerTests {
    private var kb: KnowledgeBase { KnowledgeBase.loadFromBundle(Bundle(for: FixtureAnchor.self).appMainBundle) }

    @Test func eraQuestionLeadsToThatErasTapesAndPage() {
        let plan = ChatFollowUpPlanner.plan(
            question: "What makes Europe '72 different?",
            reply: "Europe '72 was a transformative tour. I could recommend some shows!",
            kb: kb
        )
        #expect(!plan.showDates.isEmpty && plan.showDates.count <= 2)
        #expect(plan.showDates.allSatisfy { $0.hasPrefix("1972") })
        #expect(plan.actions.contains(.openEra(id: "europe-wall", label: "Europe '72 & the Wall of Sound")))
        #expect(plan.actions.contains(.ask("What's the one show to hear from 1972?")))
    }

    @Test func songQuestionLeadsToItsFamousVersionAndPage() {
        let plan = ChatFollowUpPlanner.plan(question: "Tell me about Dark Star", reply: "It's the big one.", kb: kb)
        let song = kb.song(matching: "Dark Star")
        #expect(plan.showDates == song?.famousVersions.prefix(1).map(\.date))
        #expect(plan.actions.contains(.openSong(key: "dark star", label: "Dark Star")))
        #expect(plan.actions.contains(.ask("Best Dark Star for a first-timer?")))
    }

    @Test func greetingsDoNotMatchASong() {
        #expect(kb.song(matching: "hi") == nil)
        #expect(kb.song(matching: "hey there") == nil)
        #expect(kb.song(matching: "china cat")?.key == "china cat sunflower")
        #expect(kb.song(matching: "What's the best Dark Star?")?.key == "dark star")
        let plan = ChatFollowUpPlanner.plan(question: "hi", reply: "Hey! What are you in the mood for?", kb: kb)
        #expect(plan.actions == [.ask("Pick one show for tonight")])
    }

    @Test func genericChatStillOffersANextStep() {
        let plan = ChatFollowUpPlanner.plan(question: "hey there", reply: "Hi! Ask me anything.", kb: kb)
        #expect(plan.showDates.isEmpty)
        #expect(plan.actions == [.ask("Pick one show for tonight")])
    }

    @Test func actionsRoundTripThroughRecord() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let record = ChatMessageRecord(role: "assistant", text: "x")
        container.mainContext.insert(record)
        #expect(record.actions.isEmpty)
        record.actions = [.openEra(id: "brent", label: "The Brent Years"), .ask("Pick one show for tonight")]
        try container.mainContext.save()
        #expect(record.actions == [.openEra(id: "brent", label: "The Brent Years"), .ask("Pick one show for tonight")])
    }
}
