import Foundation
import Observation
import SwiftData

/// Dependency container for the whole app. Injected via `.environment(...)`.
@Observable
final class AppEnvironment {
    /// The environment the running app is using — the hook for entry points
    /// SwiftUI doesn't own (App Intents, the CarPlay scene). Held weakly and
    /// read fresh at each use.
    private(set) static weak var current: AppEnvironment?
    let modelContainer: ModelContainer
    let cache: CacheStore
    let history: HistoryStore
    let library: LibraryStore
    let smartCollections: SmartCollectionStore
    let journeys: JourneyStore
    let downloads: DownloadManager
    let playerEngine: PlayerEngine
    let knowledgeBase: KnowledgeBase
    let catalog: any ShowCatalog
    /// The notesfile, when this build knows where it lives (Info.plist `NetheadURL`).
    let api: NetheadAPIClient?
    let sync: SyncEngine

    let recordingProvider: any LiveRecordingProvider
    let metadataProvider: any MetadataProvider
    let streamingProvider: any StreamingProvider
    var aiProvider: any AIProvider
    let authProvider: any AuthProvider
    let socialProvider: any SocialProvider

    init(modelContainer: ModelContainer,
         knowledgeBase: KnowledgeBase = KnowledgeBase.loadFromBundle(),
         catalog: any ShowCatalog = MockShowCatalog(),
         downloads: DownloadManager,
         recordingProvider: any LiveRecordingProvider,
         metadataProvider: any MetadataProvider,
         streamingProvider: any StreamingProvider,
         aiProvider: any AIProvider,
         authProvider: any AuthProvider,
         socialProvider: any SocialProvider = MockSocialProvider(),
         api: NetheadAPIClient? = nil,
         syncTransport: any SyncTransport = NoSyncTransport()) {
        self.modelContainer = modelContainer
        self.knowledgeBase = knowledgeBase
        self.catalog = catalog
        self.cache = CacheStore(container: modelContainer)
        self.history = HistoryStore(container: modelContainer)
        self.library = LibraryStore(container: modelContainer)
        self.smartCollections = SmartCollectionStore(container: modelContainer)
        self.journeys = JourneyStore(container: modelContainer)
        self.downloads = downloads
        self.playerEngine = PlayerEngine(streaming: streamingProvider)
        self.recordingProvider = recordingProvider
        self.metadataProvider = metadataProvider
        self.streamingProvider = streamingProvider
        self.aiProvider = aiProvider
        self.authProvider = authProvider
        self.socialProvider = socialProvider
        self.api = api
        self.sync = SyncEngine(container: modelContainer, library: library, transport: syncTransport, auth: authProvider)

        Self.current = self
        history.loadTasteProfile()
        playerEngine.onListeningEvent = { [weak history] show, track, seconds, completed in
            history?.record(show: show, track: track, seconds: seconds, completed: completed)
        }
        // Shelf edits go up to the notesfile a few seconds after they land.
        library.onMutation = { [weak sync] in sync?.scheduleAfterMutation() }
    }

    static func live() -> AppEnvironment {
        CloudStoreMigrator.migrateIfNeeded()
        // Shelves follow a signed-in head through the notesfile now; the old
        // cloud store opens local-only (same file, nothing moves).
        let container = ModelContainerFactory.make(cloudSync: false)
        SyncSchemaBackfill.runIfNeeded(container: container)
        let api = NetheadAPIClient()
        let cache = CacheStore(container: container)
        let archive = ArchiveShowProvider(cache: cache)
        let catalog = CatalogStore()
        let kb = KnowledgeBase.loadFromBundle()
        let downloads = DownloadManager(container: container)
        let recordingProvider = CatalogFirstShowProvider(catalog: catalog, fallback: archive)
        let environment = AppEnvironment(
            modelContainer: container,
            knowledgeBase: kb,
            catalog: catalog,
            downloads: downloads,
            recordingProvider: recordingProvider,
            metadataProvider: archive,
            streamingProvider: OfflineFirstStreamingProvider(store: downloads.store,
                                                            fallback: ArchiveStreamingProvider()),
            aiProvider: CompositeAIProvider(knowledgeBase: kb),
            authProvider: NetheadAuthProvider(api: api),
            api: api,
            syncTransport: api ?? NoSyncTransport()
        )
        downloads.reconcileOnLaunch()
        return environment
    }

    static func mock() -> AppEnvironment {
        let container = ModelContainerFactory.make(inMemory: true)
        let mockRecording = MockRecordingProvider()
        return AppEnvironment(
            modelContainer: container,
            // Ephemeral session: never touch the real background session from
            // previews/tests (duplicate background identifiers are an error).
            downloads: DownloadManager(container: container,
                                       makeSession: { _ in URLSession(configuration: .ephemeral) }),
            recordingProvider: mockRecording,
            metadataProvider: mockRecording,
            streamingProvider: MockStreamingProvider(),
            aiProvider: MockAIProvider(),
            authProvider: MockAuthProvider()
        )
    }
}
