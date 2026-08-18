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
        var lines = ["# Shakedown Journal", ""]
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
