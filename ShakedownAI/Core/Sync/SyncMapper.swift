import Foundation

/// Model rows ↔ the notesfile's wire rows. Pure, so it's testable without a store.
nonisolated enum SyncMapper {
    static func id(_ uuid: UUID) -> String { uuid.uuidString.uppercased() }
    static func uuid(_ text: String) -> UUID? { UUID(uuidString: text) }

    static func shelf(_ c: ShowCollectionSnapshot) -> SyncShelf {
        SyncShelf(id: id(c.id), name: c.name, blurb: c.blurb, iconName: c.iconName, isPrivate: false,
                  createdAt: NetheadDates.string(c.createdAt), updatedAt: NetheadDates.string(c.updatedAt), deletedAt: nil)
    }

    static func shelfItem(_ i: CollectionItemSnapshot) -> SyncShelfItem {
        SyncShelfItem(id: id(i.id), shelfId: id(i.collectionID), showIdentifier: i.showIdentifier, showId: nil,
                      showDate: i.showDate.map(NetheadDates.day), displayName: i.displayName, sortIndex: i.sortIndex,
                      addedAt: NetheadDates.string(i.addedAt), updatedAt: NetheadDates.string(i.updatedAt), deletedAt: nil)
    }

    static func mixtape(_ p: PlaylistSnapshot) -> SyncMixtape {
        SyncMixtape(id: id(p.id), name: p.name, blurb: p.blurb, iconName: p.iconName, isPrivate: false,
                    createdAt: NetheadDates.string(p.createdAt), updatedAt: NetheadDates.string(p.updatedAt), deletedAt: nil)
    }

    static func mixtapeItem(_ i: PlaylistItemSnapshot) -> SyncMixtapeItem {
        SyncMixtapeItem(id: id(i.id), mixtapeId: id(i.playlistID), showIdentifier: i.showIdentifier, fileName: i.fileName,
                        trackTitle: i.trackTitle, songKey: i.songKey, showDateString: i.showDateString, showDisplayName: i.showDisplayName,
                        durationSeconds: i.durationSeconds, sortIndex: i.sortIndex, addedAt: NetheadDates.string(i.addedAt),
                        updatedAt: NetheadDates.string(i.updatedAt), deletedAt: nil)
    }

    static func journal(_ e: JournalSnapshot) -> SyncJournalEntry {
        SyncJournalEntry(id: id(e.id), showIdentifier: e.showIdentifier, showId: nil, showDate: e.showDate.map(NetheadDates.day),
                         showDisplayName: e.showDisplayName, body: e.body, mood: e.mood, createdAt: NetheadDates.string(e.createdAt),
                         updatedAt: NetheadDates.string(e.updatedAt), deletedAt: nil)
    }

    /// A tombstone as the notesfile wants it: the row's id, the parent, and when it went.
    static func tombstones(_ stones: [TombstoneSnapshot]) -> SyncBatch {
        var batch = SyncBatch()
        for t in stones {
            let when = NetheadDates.string(t.deletedAt)
            switch t.kind {
            case "shelf":
                batch.shelves.append(SyncShelf(id: id(t.id), name: "", blurb: "", iconName: "sparkles", isPrivate: false, createdAt: when, updatedAt: when, deletedAt: when))
            case "shelfItem":
                guard let parent = t.parentID else { continue }
                batch.shelfItems.append(SyncShelfItem(id: id(t.id), shelfId: id(parent), showIdentifier: "", showId: nil, showDate: nil, displayName: "", sortIndex: 0, addedAt: when, updatedAt: when, deletedAt: when))
            case "mixtape":
                batch.mixtapes.append(SyncMixtape(id: id(t.id), name: "", blurb: "", iconName: "music.note.list", isPrivate: false, createdAt: when, updatedAt: when, deletedAt: when))
            case "mixtapeItem":
                guard let parent = t.parentID else { continue }
                batch.mixtapeItems.append(SyncMixtapeItem(id: id(t.id), mixtapeId: id(parent), showIdentifier: "", fileName: "", trackTitle: "", songKey: "", showDateString: "", showDisplayName: "", durationSeconds: 0, sortIndex: 0, addedAt: when, updatedAt: when, deletedAt: when))
            case "journalEntry":
                batch.journalEntries.append(SyncJournalEntry(id: id(t.id), showIdentifier: "", showId: nil, showDate: nil, showDisplayName: "", body: "", mood: nil, createdAt: when, updatedAt: when, deletedAt: when))
            default:
                continue
            }
        }
        return batch
    }
}

// Plain snapshots of the model rows, so the mapper never touches SwiftData.
nonisolated struct ShowCollectionSnapshot: Sendable { var id: UUID; var name: String; var blurb: String; var iconName: String; var createdAt: Date; var updatedAt: Date }
nonisolated struct CollectionItemSnapshot: Sendable { var id: UUID; var collectionID: UUID; var showIdentifier: String; var showDate: Date?; var displayName: String; var sortIndex: Int; var addedAt: Date; var updatedAt: Date }
nonisolated struct PlaylistSnapshot: Sendable { var id: UUID; var name: String; var blurb: String; var iconName: String; var createdAt: Date; var updatedAt: Date }
nonisolated struct PlaylistItemSnapshot: Sendable { var id: UUID; var playlistID: UUID; var showIdentifier: String; var fileName: String; var trackTitle: String; var songKey: String; var showDateString: String; var showDisplayName: String; var durationSeconds: Double; var sortIndex: Int; var addedAt: Date; var updatedAt: Date }
nonisolated struct JournalSnapshot: Sendable { var id: UUID; var showIdentifier: String; var showDate: Date?; var showDisplayName: String; var body: String; var mood: String?; var createdAt: Date; var updatedAt: Date }
nonisolated struct TombstoneSnapshot: Sendable { var id: UUID; var kind: String; var parentID: UUID?; var deletedAt: Date }
