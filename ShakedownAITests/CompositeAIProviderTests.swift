import Foundation
import Testing
@testable import ShakedownAI

/// The composite brain tries the on-device model only when it's ready, and
/// falls through to the offline brain on any failure — so AI features never
/// break and never need a key.
struct CompositeAIProviderTests {

    /// A stand-in tier: answers with its own name, or throws when told to.
    private final class StubAI: AIProvider {
        let name: String
        var fails: Bool
        var calls = 0

        init(name: String, fails: Bool = false) {
            self.name = name
            self.fails = fails
        }

        private func gate() throws {
            calls += 1
            if fails { throw AIError.unavailable }
        }

        func chatReply(messages: [ChatTurn], grounding: GroundingContext) async throws -> AsyncThrowingStream<String, any Error> {
            try gate()
            let name = self.name
            return AsyncThrowingStream { continuation in
                continuation.yield(name)
                continuation.finish()
            }
        }

        func recommend(query: String?, profile: TasteSnapshot, candidates: [Show]) async throws -> Recommendation {
            try gate()
            return Recommendation(chosenIdentifier: candidates[0].identifier, narrative: name, hook: name, listenFor: [])
        }

        func showGuide(for detail: RecordingDetail, show: Show?) async throws -> ShowGuide {
            try gate()
            return ShowGuide(overallMood: name, historicalContext: "", musicalHighlights: [], bestTransitions: [],
                             improvisationRating: 3, accessibility: "", recordingNotes: "", listenFor: [],
                             fanConsensus: "", recommendedTracks: [])
        }

        func parseSearchIntent(_ text: String) async throws -> SearchFilters {
            try gate()
            return SearchFilters(freeText: name)
        }

        func curateCollection(brief: CollectionBrief, candidates: [CollectionCandidate]) async throws -> CuratedCollection {
            try gate()
            return SmartCollectionCurator.curate(brief: brief, candidates: candidates)
        }
    }

    private func drain(_ stream: AsyncThrowingStream<String, any Error>) async throws -> String {
        var text = ""
        for try await chunk in stream { text += chunk }
        return text
    }

    @Test func onDeviceAnswersWhenReady() async throws {
        let onDevice = StubAI(name: "On-device")
        let local = StubAI(name: "Offline Brain")
        let ai = CompositeAIProvider(onDevice: onDevice, onDeviceReady: { true }, local: local)

        #expect(ai.name == "On-device")
        #expect(ai.isOnDeviceActive)
        let rec = try await ai.recommend(query: nil, profile: .empty, candidates: [MockData.cornell])
        #expect(rec.narrative == "On-device")
        #expect(try await ai.parseSearchIntent("dark star").freeText == "On-device")
        #expect(local.calls == 0)
    }

    @Test func fallsThroughWhenOnDeviceThrows() async throws {
        let onDevice = StubAI(name: "On-device", fails: true)
        let local = StubAI(name: "Offline Brain")
        let ai = CompositeAIProvider(onDevice: onDevice, onDeviceReady: { true }, local: local)

        let rec = try await ai.recommend(query: nil, profile: .empty, candidates: [MockData.cornell])
        #expect(rec.narrative == "Offline Brain")
        #expect(try await ai.parseSearchIntent("dark star").freeText == "Offline Brain")
        #expect(onDevice.calls == 2)
        #expect(local.calls == 2)
    }

    @Test func skipsOnDeviceWhenNotReady() async throws {
        let onDevice = StubAI(name: "On-device")
        let local = StubAI(name: "Offline Brain")
        let ai = CompositeAIProvider(onDevice: onDevice, onDeviceReady: { false }, local: local)

        #expect(ai.name == "Offline Brain")
        #expect(!ai.isOnDeviceActive)
        let rec = try await ai.recommend(query: nil, profile: .empty, candidates: [MockData.cornell])
        #expect(rec.narrative == "Offline Brain")
        #expect(onDevice.calls == 0)
    }

    @Test func noOnDeviceTierAtAll() async throws {
        let local = StubAI(name: "Offline Brain")
        let ai = CompositeAIProvider(onDevice: nil, onDeviceReady: { true }, local: local)
        #expect(ai.name == "Offline Brain")
        let text = try await drain(try await ai.chatReply(messages: [ChatTurn(role: .user, text: "hi")], grounding: .empty))
        #expect(text == "Offline Brain")
    }

    @Test func chatFallsThroughOnStreamFailure() async throws {
        let onDevice = StubAI(name: "On-device", fails: true)
        let local = StubAI(name: "Offline Brain")
        let ai = CompositeAIProvider(onDevice: onDevice, onDeviceReady: { true }, local: local)
        let text = try await drain(try await ai.chatReply(messages: [ChatTurn(role: .user, text: "hi")], grounding: .empty))
        #expect(text == "Offline Brain")
    }
}
