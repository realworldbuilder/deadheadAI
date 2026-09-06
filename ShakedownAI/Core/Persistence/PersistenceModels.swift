import Foundation
import OSLog
import SwiftData

// MARK: - Cache

@Model
final class CachedShowSearch {
    @Attribute(.unique) var queryKey: String
    var payload: Data
    var fetchedAt: Date

    init(queryKey: String, payload: Data, fetchedAt: Date = .now) {
        self.queryKey = queryKey
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}

@Model
final class CachedRecordingMetadata {
    @Attribute(.unique) var identifier: String
    var payload: Data
    var fetchedAt: Date

    init(identifier: String, payload: Data, fetchedAt: Date = .now) {
        self.identifier = identifier
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}

/// The AI-written "Why this show?" story for a day's hero tape, keyed by
/// day + identifier so a relaunch never re-bills the same narrative.
@Model
final class CachedHeroNarrative {
    @Attribute(.unique) var key: String
    var payload: Data
    var fetchedAt: Date

    init(key: String, payload: Data, fetchedAt: Date = .now) {
        self.key = key
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}

// MARK: - Journal

// JournalEntry, ShowCollection, CollectionItem, Playlist, and PlaylistItem are
// the rows the notesfile keeps in step with the phone (see Core/Sync): every
// row has a client UUID, an `updatedAt` for last-writer-wins, and `needsPush`
// while the notesfile hasn't seen the latest edit. No unique attributes,
// every property defaulted, relationships optional — the store was once
// CloudKit-mirrored and old installs still open it. Duplicates are collapsed
// by LibraryStore.dedupAfterSync().

@Model
final class JournalEntry {
    var id: UUID = UUID()
    var showIdentifier: String = ""
    var showDate: Date?
    var showDisplayName: String = ""
    var body: String = ""
    var mood: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var needsPush: Bool = true

    init(showIdentifier: String,
         showDate: Date?,
         showDisplayName: String,
         body: String,
         mood: String? = nil) {
        self.id = UUID()
        self.showIdentifier = showIdentifier
        self.showDate = showDate
        self.showDisplayName = showDisplayName
        self.body = body
        self.mood = mood
        self.createdAt = .now
        self.updatedAt = .now
    }
}

// MARK: - Collections

@Model
final class ShowCollection {
    var id: UUID = UUID()
    var name: String = ""
    var blurb: String = ""
    var iconName: String = "sparkles"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var needsPush: Bool = true
    @Relationship(deleteRule: .cascade, inverse: \CollectionItem.collection)
    var items: [CollectionItem]? = []

    init(name: String, blurb: String = "", iconName: String = "sparkles") {
        self.id = UUID()
        self.name = name
        self.blurb = blurb
        self.iconName = iconName
        self.createdAt = .now
        self.updatedAt = .now
        self.needsPush = true
        self.items = []
    }
}

@Model
final class CollectionItem {
    var id: UUID = UUID()
    var showIdentifier: String = ""
    var showDate: Date?
    var displayName: String = ""
    var addedAt: Date = Date.now
    var sortIndex: Int = 0
    var updatedAt: Date = Date.now
    var needsPush: Bool = true
    var collection: ShowCollection?

    init(showIdentifier: String, showDate: Date?, displayName: String, sortIndex: Int) {
        self.id = UUID()
        self.updatedAt = .now
        self.needsPush = true
        self.showIdentifier = showIdentifier
        self.showDate = showDate
        self.displayName = displayName
        self.addedAt = .now
        self.sortIndex = sortIndex
    }
}

// MARK: - Playlists (track-level, CloudKit-synced)

/// A user playlist of individual tracks, possibly spanning many shows.
/// Cloud rules apply: no unique attributes, every property defaulted,
/// relationships optional; LibraryStore.dedupAfterSync() collapses dupes.
@Model
final class Playlist {
    var id: UUID = UUID()
    var name: String = ""
    var blurb: String = ""
    var iconName: String = "music.note.list"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var needsPush: Bool = true
    @Relationship(deleteRule: .cascade, inverse: \PlaylistItem.playlist)
    var items: [PlaylistItem]? = []

    init(name: String, blurb: String = "", iconName: String = "music.note.list") {
        self.id = UUID()
        self.name = name
        self.blurb = blurb
        self.iconName = iconName
        self.createdAt = .now
        self.updatedAt = .now
        self.needsPush = true
        self.items = []
    }
}

/// One track on a playlist. Snapshots everything needed to display and play
/// the row with no network: streaming only needs (showIdentifier, fileName).
@Model
final class PlaylistItem {
    var id: UUID = UUID()
    var updatedAt: Date = Date.now
    var needsPush: Bool = true
    var showIdentifier: String = ""
    var fileName: String = ""
    var trackTitle: String = ""
    var songKey: String = ""
    var showDateString: String = ""
    var showDisplayName: String = ""
    var durationSeconds: Double = 0
    var addedAt: Date = Date.now
    var sortIndex: Int = 0
    var playlist: Playlist?

    /// Identity of the underlying track — the dedup key after a sync.
    var trackKey: String { showIdentifier + "|" + fileName }

    init(showIdentifier: String, fileName: String, trackTitle: String, songKey: String,
         showDateString: String, showDisplayName: String, durationSeconds: Double, sortIndex: Int) {
        self.id = UUID()
        self.updatedAt = .now
        self.needsPush = true
        self.showIdentifier = showIdentifier
        self.fileName = fileName
        self.trackTitle = trackTitle
        self.songKey = songKey
        self.showDateString = showDateString
        self.showDisplayName = showDisplayName
        self.durationSeconds = durationSeconds
        self.addedAt = .now
        self.sortIndex = sortIndex
    }
}

extension PlaylistItem {
    /// Rebuilds the playable domain pair from the snapshot — StreamingProvider
    /// only needs (showIdentifier, fileName), so playlist rows play with no
    /// network fetch, online or off.
    var queueEntry: PlayerQueueEntry {
        let show = Show(identifier: showIdentifier,
                        title: showDisplayName,
                        date: IADates.parse(showDateString),
                        dateString: showDateString.isEmpty ? nil : showDateString,
                        venue: nil,
                        location: nil,
                        year: Int(showDateString.prefix(4)),
                        avgRating: nil, numReviews: nil, downloads: nil, source: nil)
        let track = Track(fileName: fileName,
                          title: trackTitle,
                          trackNumber: nil,
                          durationSeconds: durationSeconds > 0 ? durationSeconds : nil)
        return PlayerQueueEntry(show: show, track: track)
    }
}

@Model
final class SmartCollectionRecord {
    /// One row per planner slot ("daypart", "calendar", "trend", "deep-cut").
    @Attribute(.unique) var slotID: String
    /// Encoded SmartCollection.
    var payload: Data
    /// The DayContext key these shelves were generated for.
    var contextKey: String
    var generatedAt: Date
    var sortIndex: Int

    init(slotID: String, payload: Data, contextKey: String, generatedAt: Date, sortIndex: Int) {
        self.slotID = slotID
        self.payload = payload
        self.contextKey = contextKey
        self.generatedAt = generatedAt
        self.sortIndex = sortIndex
    }
}

// MARK: - Listening history & taste

@Model
final class ListeningEvent {
    var showIdentifier: String
    var showDisplayName: String
    var trackTitle: String
    /// Normalized song name ("scarlet begonias") for taste aggregation.
    var songKey: String
    var showYear: Int?
    var venue: String?
    var startedAt: Date
    var secondsListened: Double
    var completed: Bool

    init(showIdentifier: String,
         showDisplayName: String,
         trackTitle: String,
         songKey: String,
         showYear: Int?,
         venue: String?,
         startedAt: Date = .now,
         secondsListened: Double = 0,
         completed: Bool = false) {
        self.showIdentifier = showIdentifier
        self.showDisplayName = showDisplayName
        self.trackTitle = trackTitle
        self.songKey = songKey
        self.showYear = showYear
        self.venue = venue
        self.startedAt = startedAt
        self.secondsListened = secondsListened
        self.completed = completed
    }
}

@Model
final class TasteProfileRecord {
    /// Singleton row — always keyed "main".
    @Attribute(.unique) var key: String
    /// Encoded TasteSnapshot.
    var payload: Data
    var lastUpdated: Date

    init(key: String = "main", payload: Data, lastUpdated: Date = .now) {
        self.key = key
        self.payload = payload
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Journeys

@Model
final class JourneyState {
    @Attribute(.unique) var journeyID: String
    var startedAt: Date
    var currentDayIndex: Int
    var completedDayIndicesData: Data
    var completedAt: Date?

    init(journeyID: String) {
        self.journeyID = journeyID
        self.startedAt = .now
        self.currentDayIndex = 0
        self.completedDayIndicesData = (try? JSONEncoder().encode([Int]())) ?? Data()
        self.completedAt = nil
    }

    var completedDayIndices: [Int] {
        get { (try? JSONDecoder().decode([Int].self, from: completedDayIndicesData)) ?? [] }
        set { completedDayIndicesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

// MARK: - Chat

@Model
final class ChatThread {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ChatMessageRecord.thread)
    var messages: [ChatMessageRecord]

    init(title: String) {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.messages = []
    }
}

@Model
final class ChatMessageRecord {
    var role: String   // "user" | "assistant"
    var text: String
    var createdAt: Date
    var thread: ChatThread?
    /// JSON-encoded `[Show]` the reply recommended (assistant rows only);
    /// nil for user turns and for rows written before cards existed.
    var showsData: Data?
    /// JSON-encoded `[ChatAction]` chips shown beneath the reply; nil when none.
    var actionsData: Data?

    init(role: String, text: String, createdAt: Date = .now) {
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }

    var shows: [Show] {
        get { showsData.flatMap { try? JSONDecoder().decode([Show].self, from: $0) } ?? [] }
        set { showsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var actions: [ChatAction] {
        get { actionsData.flatMap { try? JSONDecoder().decode([ChatAction].self, from: $0) } ?? [] }
        set { actionsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }
}

// MARK: - Account

@Model
final class LocalAccount {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var avatarSeed: Int
    var appleUserID: String?
    var createdAt: Date

    init(displayName: String, avatarSeed: Int = Int.random(in: 0...9999), appleUserID: String? = nil) {
        self.id = UUID()
        self.displayName = displayName
        self.avatarSeed = avatarSeed
        self.appleUserID = appleUserID
        self.createdAt = .now
    }
}

// MARK: - Downloads

/// One downloaded (or downloading) recording. Device-local only — audio files
/// don't sync. Carries full Show and RecordingDetail snapshots so a downloaded
/// show opens and plays with no network, even after the metadata cache expires.
@Model
final class DownloadedShowRecord {
    @Attribute(.unique) var identifier: String
    /// Encoded Show.
    var showPayload: Data
    /// Encoded RecordingDetail — the offline track list.
    var detailPayload: Data
    var statusRaw: String   // DownloadStore.ShowStatus
    var requestedAt: Date
    var completedAt: Date?
    var totalBytes: Int64
    @Relationship(deleteRule: .cascade, inverse: \DownloadedTrackRecord.show)
    var trackRecords: [DownloadedTrackRecord]

    init(identifier: String, showPayload: Data, detailPayload: Data) {
        self.identifier = identifier
        self.showPayload = showPayload
        self.detailPayload = detailPayload
        self.statusRaw = "queued"
        self.requestedAt = .now
        self.completedAt = nil
        self.totalBytes = 0
        self.trackRecords = []
    }
}

@Model
final class DownloadedTrackRecord {
    /// DownloadLocations.trackKey(identifier:fileName:).
    @Attribute(.unique) var key: String
    var fileName: String
    var statusRaw: String   // DownloadStore.TrackStatus
    var bytes: Int64
    var errorText: String?
    var show: DownloadedShowRecord?

    init(key: String, fileName: String) {
        self.key = key
        self.fileName = fileName
        self.statusRaw = "pending"
        self.bytes = 0
        self.errorText = nil
    }
}

// MARK: - Sync tombstones

/// A row the phone deleted that the notesfile hasn't heard about yet. Lives
/// in the local store; SyncEngine sends it up and drops it once acked.
@Model
final class SyncTombstone {
    @Attribute(.unique) var id: UUID
    /// "shelf" | "shelfItem" | "mixtape" | "mixtapeItem" | "journalEntry"
    var kind: String
    /// The shelf or mix tape an item belonged to, so the notesfile can place it.
    var parentID: UUID?
    var deletedAt: Date

    init(id: UUID, kind: String, parentID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.parentID = parentID
        self.deletedAt = .now
    }
}

// MARK: - Container factory

enum ModelContainerFactory {
    /// User shelves, mix tapes & journal — the rows the notesfile syncs. They
    /// still live in their own store file (it was CloudKit's once; nothing moves).
    static let cloudModels: [any PersistentModel.Type] = [
        JournalEntry.self,
        ShowCollection.self,
        CollectionItem.self,
        Playlist.self,
        PlaylistItem.self,
    ]

    /// Everything device-local: caches, history/taste, smart shelves,
    /// journeys, chat, accounts.
    static let localModels: [any PersistentModel.Type] = [
        CachedShowSearch.self,
        CachedRecordingMetadata.self,
        CachedHeroNarrative.self,
        SmartCollectionRecord.self,
        ListeningEvent.self,
        TasteProfileRecord.self,
        JourneyState.self,
        ChatThread.self,
        ChatMessageRecord.self,
        LocalAccount.self,
        SyncTombstone.self,
        DownloadedShowRecord.self,
        DownloadedTrackRecord.self,
    ]

    static var allModels: [any PersistentModel.Type] { localModels + cloudModels }

    static let cloudKitContainerID = "iCloud.com.deadhead.ai"

    /// The legacy single-store path — must stay pinned here or existing
    /// installs lose their caches, history, and journeys.
    static var localStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    static var cloudStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "shakedown-cloud.store")
    }

    static func make(inMemory: Bool = false, cloudSync: Bool = false) -> ModelContainer {
        let schema = Schema(allModels)
        let log = Logger(subsystem: "ai.deadheads", category: "persistence")

        func inMemoryContainer() -> ModelContainer {
            let local = ModelConfiguration("local", schema: Schema(localModels),
                                           isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let cloud = ModelConfiguration("cloud", schema: Schema(cloudModels),
                                           isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [local, cloud])
        }
        if inMemory { return inMemoryContainer() }

        // Without the iCloud entitlement, CloudKit doesn't fail container
        // creation — it traps later on a background queue, uncatchably. Our
        // simulator builds are always unsigned (no entitlement at runtime), so
        // never open .private there; device builds are signed with it or fail
        // visibly at signing.
        #if targetEnvironment(simulator)
        let sync = false
        if cloudSync { log.notice("Simulator build: iCloud sync stays off (no runtime entitlement)") }
        #else
        let sync = cloudSync
        #endif

        func diskConfigs(sync: Bool) -> [ModelConfiguration] {
            let local = ModelConfiguration("local", schema: Schema(localModels),
                                           url: localStoreURL, cloudKitDatabase: .none)
            let cloud = ModelConfiguration("cloud", schema: Schema(cloudModels),
                                           url: cloudStoreURL,
                                           cloudKitDatabase: sync ? .private(cloudKitContainerID) : .none)
            return [local, cloud]
        }
        do {
            return try ModelContainer(for: schema, configurations: diskConfigs(sync: sync))
        } catch {
            if sync {
                log.error("CloudKit container failed (\(String(describing: error), privacy: .public)); retrying without sync")
                if let container = try? ModelContainer(for: schema, configurations: diskConfigs(sync: false)) {
                    return container
                }
            }
            // A corrupt store should not brick the app: fall back to in-memory.
            log.fault("Persistent container failed (\(String(describing: error), privacy: .public)); falling back to in-memory")
            return inMemoryContainer()
        }
    }
}
