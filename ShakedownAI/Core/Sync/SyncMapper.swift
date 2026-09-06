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
nonisolated struct TombstoneSnapshot: Sendable { var id: UUID; var kind: String; var parentID: UUID?; var deletedAt: Date }
