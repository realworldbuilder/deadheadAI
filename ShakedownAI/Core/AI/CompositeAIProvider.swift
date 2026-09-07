import Foundation

/// Two brains, best-available first: Apple's free on-device model when the
/// hardware and the user's settings provide it, then the offline knowledge
/// brain. The on-device tier falls through on any failure, so AI features
/// never break, never need a key, and never send a word off the phone.
final class CompositeAIProvider: AIProvider {
    private let local: any AIProvider
    /// Apple's on-device model, when the SDK and the hardware both provide it.
    /// Held as an existential so this class stays available back to iOS 18.
    private let onDevice: (any AIProvider)?
    /// Re-checked on every call — the user can switch Apple Intelligence off,
    /// or the weights may still be downloading.
    private let onDeviceReady: () -> Bool

    init(onDevice: (any AIProvider)?, onDeviceReady: @escaping () -> Bool, local: any AIProvider) {
        self.onDevice = onDevice
        self.onDeviceReady = onDeviceReady
        self.local = local
    }

    convenience init(knowledgeBase: KnowledgeBase) {
        let local = LocalKnowledgeAI(knowledgeBase: knowledgeBase)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            self.init(onDevice: AppleOnDeviceAI(knowledgeBase: knowledgeBase),
                      onDeviceReady: { AppleOnDeviceAI.isReady },
                      local: local)
            return
        }
        #endif
        self.init(onDevice: nil, onDeviceReady: { false }, local: local)
    }

    /// The on-device model, but only when it can actually answer right now.
    private var readyOnDevice: (any AIProvider)? {
        guard let onDevice, onDeviceReady() else { return nil }
        return onDevice
    }

    var name: String { readyOnDevice?.name ?? local.name }
    /// True when the on-device model would answer the next call.
    var isOnDeviceActive: Bool { readyOnDevice != nil }

    func recommend(query: String?, profile: TasteSnapshot, candidates: [Show]) async throws -> Recommendation {
        if let onDevice = readyOnDevice,
           let result = try? await onDevice.recommend(query: query, profile: profile, candidates: candidates) {
            return result
        }
        return try await local.recommend(query: query, profile: profile, candidates: candidates)
    }

    func showGuide(for detail: RecordingDetail, show: Show?) async throws -> ShowGuide {
        if let onDevice = readyOnDevice, let result = try? await onDevice.showGuide(for: detail, show: show) {
            return result
        }
        return try await local.showGuide(for: detail, show: show)
    }

    func parseSearchIntent(_ text: String) async throws -> SearchFilters {
        if let onDevice = readyOnDevice, let result = try? await onDevice.parseSearchIntent(text) {
            return result
        }
        return try await local.parseSearchIntent(text)
    }

    func curateCollection(brief: CollectionBrief, candidates: [CollectionCandidate]) async throws -> CuratedCollection {
        if let onDevice = readyOnDevice,
           let result = try? await onDevice.curateCollection(brief: brief, candidates: candidates) {
            return result
        }
        return try await local.curateCollection(brief: brief, candidates: candidates)
    }

    func chatReply(messages: [ChatTurn], grounding: GroundingContext) async throws -> AsyncThrowingStream<String, any Error> {
        if let onDevice = readyOnDevice {
            do {
                return try await onDevice.chatReply(messages: messages, grounding: grounding)
            } catch {
                // fall through to the offline brain
            }
        }
        return try await local.chatReply(messages: messages, grounding: grounding)
    }
}
