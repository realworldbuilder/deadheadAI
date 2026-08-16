import Foundation
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

// MARK: - Journal

@Model
final class JournalEntry {
    @Attribute(.unique) var id: UUID
    var showIdentifier: String
    var showDate: Date?
    var showDisplayName: String
    var body: String
    var mood: String?
    var createdAt: Date
    var updatedAt: Date

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
    @Attribute(.unique) var id: UUID
    var name: String
    var blurb: String
    var iconName: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \CollectionItem.collection)
    var items: [CollectionItem]

    init(name: String, blurb: String = "", iconName: String = "sparkles") {
        self.id = UUID()
        self.name = name
        self.blurb = blurb
        self.iconName = iconName
        self.createdAt = .now
        self.items = []
    }
}

@Model
final class CollectionItem {
    var showIdentifier: String
    var showDate: Date?
    var displayName: String
    var addedAt: Date
    var sortIndex: Int
    var collection: ShowCollection?

    init(showIdentifier: String, showDate: Date?, displayName: String, sortIndex: Int) {
        self.showIdentifier = showIdentifier
        self.showDate = showDate
        self.displayName = displayName
        self.addedAt = .now
        self.sortIndex = sortIndex
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

    init(role: String, text: String, createdAt: Date = .now) {
        self.role = role
        self.text = text
        self.createdAt = createdAt
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

// MARK: - Container factory

enum ModelContainerFactory {
    static let allModels: [any PersistentModel.Type] = [
        CachedShowSearch.self,
        CachedRecordingMetadata.self,
        JournalEntry.self,
        ShowCollection.self,
        CollectionItem.self,
        SmartCollectionRecord.self,
        ListeningEvent.self,
        TasteProfileRecord.self,
        JourneyState.self,
        ChatThread.self,
        ChatMessageRecord.self,
        LocalAccount.self,
    ]

    static func make(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(allModels)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // A corrupt store should not brick the app: fall back to in-memory.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }
}
