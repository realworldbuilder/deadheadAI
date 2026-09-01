import Foundation
import SwiftData

/// Collections + journal, MainActor-only.
@Observable
final class LibraryStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = container.mainContext
    }

    // MARK: - Collections

    var collections: [ShowCollection] {
        let descriptor = FetchDescriptor<ShowCollection>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func createCollection(name: String, blurb: String = "", iconName: String = "sparkles") -> ShowCollection {
        let collection = ShowCollection(name: name, blurb: blurb, iconName: iconName)
        context.insert(collection)
        try? context.save()
        return collection
    }

    func deleteCollection(_ collection: ShowCollection) {
        context.delete(collection)
        try? context.save()
    }

    func add(show: Show, to collection: ShowCollection) {
        let existing = collection.items ?? []
        guard !existing.contains(where: { $0.showIdentifier == show.identifier }) else { return }
        let item = CollectionItem(showIdentifier: show.identifier,
                                  showDate: show.date,
                                  displayName: show.shortName,
                                  sortIndex: existing.count)
        item.collection = collection
        context.insert(item)
        try? context.save()
    }

    func remove(item: CollectionItem) {
        context.delete(item)
        try? context.save()
    }

    // MARK: - Playlists

    var playlists: [Playlist] {
        let descriptor = FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func createPlaylist(name: String, blurb: String = "", iconName: String = "music.note.list") -> Playlist {
        let playlist = Playlist(name: name, blurb: blurb, iconName: iconName)
        context.insert(playlist)
        try? context.save()
        return playlist
    }

    func deletePlaylist(_ playlist: Playlist) {
        context.delete(playlist)
        try? context.save()
    }

    /// Appends tracks from one show, in the order given, skipping tracks the
    /// playlist already holds (keyed on showIdentifier|fileName).
    func add(tracks: [Track], from show: Show, to playlist: Playlist) {
        var existingKeys = Set((playlist.items ?? []).map(\.trackKey))
        var nextIndex = ((playlist.items ?? []).map(\.sortIndex).max() ?? -1) + 1
        var inserted = false
        for track in tracks {
            let key = show.identifier + "|" + track.fileName
            guard existingKeys.insert(key).inserted else { continue }
            let item = PlaylistItem(showIdentifier: show.identifier,
                                    fileName: track.fileName,
                                    trackTitle: track.title,
                                    songKey: track.songKey,
                                    showDateString: show.dateString ?? "",
                                    showDisplayName: show.shortName,
                                    durationSeconds: track.durationSeconds ?? 0,
                                    sortIndex: nextIndex)
            item.playlist = playlist
            context.insert(item)
            nextIndex += 1
            inserted = true
        }
        if inserted { try? context.save() }
    }

    func remove(item: PlaylistItem) {
        let playlist = item.playlist
        let itemID = item.persistentModelID
        context.delete(item)
        if let playlist {
            let remaining = sortedItems(of: playlist).filter { $0.persistentModelID != itemID }
            for (index, survivor) in remaining.enumerated() where survivor.sortIndex != index {
                survivor.sortIndex = index
            }
        }
        try? context.save()
    }

    /// Swaps the item with its neighbor above (`up`) or below.
    func move(item: PlaylistItem, up: Bool) {
        guard let playlist = item.playlist else { return }
        let items = sortedItems(of: playlist)
        guard let position = items.firstIndex(where: { $0.persistentModelID == item.persistentModelID }) else { return }
        let target = up ? position - 1 : position + 1
        guard items.indices.contains(target) else { return }
        let other = items[target]
        swap(&item.sortIndex, &other.sortIndex)
        try? context.save()
    }

    /// Rewrites every item's sortIndex to the given track-key order (unlisted
    /// items keep their relative order at the end).
    func reorder(_ playlist: Playlist, toTrackKeys keys: [String]) {
        let items = sortedItems(of: playlist)
        var position: [String: Int] = [:]
        for (offset, key) in keys.enumerated() { position[key] = offset }
        let reordered = items.enumerated().sorted { lhs, rhs in
            let l = position[lhs.element.trackKey] ?? (keys.count + lhs.offset)
            let r = position[rhs.element.trackKey] ?? (keys.count + rhs.offset)
            return l < r
        }
        for (index, entry) in reordered.enumerated() where entry.element.sortIndex != index {
            entry.element.sortIndex = index
        }
        try? context.save()
    }

    func sortedItems(of playlist: Playlist) -> [PlaylistItem] {
        (playlist.items ?? []).sorted {
            ($0.sortIndex, $0.addedAt, $0.trackKey) < ($1.sortIndex, $1.addedAt, $1.trackKey)
        }
    }

    private static let seedFlagKey = "didSeedCollections"
    private static let seedNames: Set<String> = ["Favorites", "Road Trips", "Sunday Morning", "Late Night"]

    /// Seeds a few starter collections on first launch. The flag keeps a second
    /// device from re-seeding while its first iCloud import is still in flight;
    /// dedupAfterSync() collapses the races the flag can't prevent.
    func seedDefaultCollectionsIfNeeded() {
        guard collections.isEmpty, !UserDefaults.standard.bool(forKey: Self.seedFlagKey) else { return }
        createCollection(name: "Favorites", blurb: "The ones that got you.", iconName: "heart.fill")
        createCollection(name: "Road Trips", blurb: "Windows down, volume up.", iconName: "car.fill")
        createCollection(name: "Sunday Morning", blurb: "Gentle starts and Ripples.", iconName: "sun.horizon.fill")
        createCollection(name: "Late Night", blurb: "For after everyone else is asleep.", iconName: "moon.stars.fill")
        UserDefaults.standard.set(true, forKey: Self.seedFlagKey)
    }

    // MARK: - Sync dedup

    /// The cloud store has no unique constraints (CloudKit forbids them), so a
    /// sync can land duplicate rows and every device seeds its own starter
    /// shelves. Collapses duplicates deterministically — survivor is the
    /// earliest `createdAt`, tiebroken on lowest `id.uuidString` — so all
    /// devices converge on the same rows.
    func dedupAfterSync() {
        var changed = false

        // Collections: collapse by id, then collapse duplicate seed shelves by name.
        let ordered = collections.sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
        var byID: [UUID: ShowCollection] = [:]
        var seedByName: [String: ShowCollection] = [:]
        for collection in ordered {
            let survivor = byID[collection.id]
                ?? (Self.seedNames.contains(collection.name) ? seedByName[collection.name] : nil)
            if let survivor {
                // Re-parent items the survivor doesn't have before cascade
                // deletes the loser's remainder.
                let kept = Set((survivor.items ?? []).map(\.showIdentifier))
                for item in collection.items ?? [] where !kept.contains(item.showIdentifier) {
                    item.collection = survivor
                }
                context.delete(collection)
                changed = true
            } else {
                byID[collection.id] = collection
                if Self.seedNames.contains(collection.name) {
                    seedByName[collection.name] = collection
                }
            }
        }

        // Items: collapse by show within each surviving shelf, renumber sortIndex.
        for collection in byID.values {
            let items = (collection.items ?? []).sorted {
                ($0.addedAt, $0.showIdentifier) < ($1.addedAt, $1.showIdentifier)
            }
            var seen: Set<String> = []
            var index = 0
            for item in items {
                if seen.insert(item.showIdentifier).inserted {
                    if item.sortIndex != index { item.sortIndex = index; changed = true }
                    index += 1
                } else {
                    context.delete(item)
                    changed = true
                }
            }
        }

        // Playlists: collapse by id (same survivor rule); items collapse on the
        // composite showIdentifier|fileName key — NEVER the show key alone, or a
        // playlist would shrink to one track per show.
        let orderedPlaylists = playlists.sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
        var playlistByID: [UUID: Playlist] = [:]
        for playlist in orderedPlaylists {
            if let survivor = playlistByID[playlist.id] {
                let kept = Set((survivor.items ?? []).map(\.trackKey))
                for item in playlist.items ?? [] where !kept.contains(item.trackKey) {
                    item.playlist = survivor
                }
                context.delete(playlist)
                changed = true
            } else {
                playlistByID[playlist.id] = playlist
            }
        }
        for playlist in playlistByID.values {
            let items = sortedItems(of: playlist)
            var seenTracks: Set<String> = []
            var trackIndex = 0
            for item in items {
                if seenTracks.insert(item.trackKey).inserted {
                    if item.sortIndex != trackIndex { item.sortIndex = trackIndex; changed = true }
                    trackIndex += 1
                } else {
                    context.delete(item)
                    changed = true
                }
            }
        }

        // Journal: collapse by id, keeping the latest edit.
        var entriesByID: [UUID: JournalEntry] = [:]
        let orderedEntries = journalEntries.sorted {
            ($1.updatedAt, $1.createdAt) < ($0.updatedAt, $0.createdAt)
        }
        for entry in orderedEntries {
            if entriesByID[entry.id] != nil {
                context.delete(entry)
                changed = true
            } else {
                entriesByID[entry.id] = entry
            }
        }

        if changed { try? context.save() }
    }

    // MARK: - Journal

    var journalEntries: [JournalEntry] {
        let descriptor = FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func entries(forShow identifier: String) -> [JournalEntry] {
        journalEntries.filter { $0.showIdentifier == identifier }
    }

    @discardableResult
    func addJournalEntry(show: Show, body: String, mood: String?) -> JournalEntry {
        let entry = JournalEntry(showIdentifier: show.identifier,
                                 showDate: show.date,
                                 showDisplayName: show.shortName,
                                 body: body,
                                 mood: mood)
        context.insert(entry)
        try? context.save()
        return entry
    }

    func updateJournalEntry(_ entry: JournalEntry, body: String, mood: String?) {
        entry.body = body
        entry.mood = mood
        entry.updatedAt = .now
        try? context.save()
    }

    func deleteJournalEntry(_ entry: JournalEntry) {
        context.delete(entry)
        try? context.save()
    }

    /// Markdown export of the whole journal.
    func journalMarkdown() -> String {
        var lines = ["# TapeTree Journal", ""]
        for entry in journalEntries.sorted(by: { $0.createdAt < $1.createdAt }) {
            lines.append("## \(entry.showDisplayName)")
            if let mood = entry.mood, !mood.isEmpty {
                lines.append("*Mood: \(mood)*")
            }
            lines.append("*Written \(entry.createdAt.formatted(date: .long, time: .omitted))*")
            lines.append("")
            lines.append(entry.body)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
