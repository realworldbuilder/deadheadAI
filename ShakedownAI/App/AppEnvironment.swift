import Foundation
import Observation
import SwiftData

/// Dependency container for the whole app. Injected via `.environment(...)`.
@Observable
final class AppEnvironment {
    let modelContainer: ModelContainer
    let cache: CacheStore
    let history: HistoryStore
    let library: LibraryStore
    let smartCollections: SmartCollectionStore
    let journeys: JourneyStore
    let playerEngine: PlayerEngine
    let knowledgeBase: KnowledgeBase

    let recordingProvider: any LiveRecordingProvider
    let metadataProvider: any MetadataProvider
    let streamingProvider: any StreamingProvider
    var aiProvider: any AIProvider
    let authProvider: any AuthProvider
    let socialProvider: any SocialProvider

    init(modelContainer: ModelContainer,
         knowledgeBase: KnowledgeBase = KnowledgeBase.loadFromBundle(),
         recordingProvider: any LiveRecordingProvider,
         metadataProvider: any MetadataProvider,
         streamingProvider: any StreamingProvider,
         aiProvider: any AIProvider,
         authProvider: any AuthProvider,
         socialProvider: any SocialProvider = MockSocialProvider()) {
        self.modelContainer = modelContainer
        self.knowledgeBase = knowledgeBase
        self.cache = CacheStore(container: modelContainer)
        self.history = HistoryStore(container: modelContainer)
        self.library = LibraryStore(container: modelContainer)
        self.smartCollections = SmartCollectionStore(container: modelContainer)
        self.journeys = JourneyStore(container: modelContainer)
        self.playerEngine = PlayerEngine(streaming: streamingProvider)
        self.recordingProvider = recordingProvider
        self.metadataProvider = metadataProvider
        self.streamingProvider = streamingProvider
        self.aiProvider = aiProvider
        self.authProvider = authProvider
        self.socialProvider = socialProvider

        history.loadTasteProfile()
        playerEngine.onListeningEvent = { [weak history] show, track, seconds, completed in
            history?.record(show: show, track: track, seconds: seconds, completed: completed)
        }
    }

    static func live() -> AppEnvironment {
        let container = ModelContainerFactory.make()
        let cache = CacheStore(container: container)
        let archive = ArchiveShowProvider(cache: cache)
        let kb = KnowledgeBase.loadFromBundle()
        return AppEnvironment(
            modelContainer: container,
            knowledgeBase: kb,
            recordingProvider: archive,
            metadataProvider: archive,
            streamingProvider: ArchiveStreamingProvider(),
            aiProvider: CompositeAIProvider(knowledgeBase: kb),
            authProvider: MockAuthProvider()
        )
    }

    static func mock() -> AppEnvironment {
        let container = ModelContainerFactory.make(inMemory: true)
        let mockRecording = MockRecordingProvider()
        return AppEnvironment(
            modelContainer: container,
            recordingProvider: mockRecording,
            metadataProvider: mockRecording,
            streamingProvider: MockStreamingProvider(),
            aiProvider: MockAIProvider(),
            authProvider: MockAuthProvider()
        )
    }
}
