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
        guard !collection.items.contains(where: { $0.showIdentifier == show.identifier }) else { return }
        let item = CollectionItem(showIdentifier: show.identifier,
                                  showDate: show.date,
                                  displayName: show.shortName,
                                  sortIndex: collection.items.count)
        item.collection = collection
        context.insert(item)
        try? context.save()
    }

    func remove(item: CollectionItem) {
        context.delete(item)
        try? context.save()
    }

    /// Seeds a few starter collections on first launch.
    func seedDefaultCollectionsIfNeeded() {
        guard collections.isEmpty else { return }
        createCollection(name: "Favorites", blurb: "The ones that got you.", iconName: "heart.fill")
        createCollection(name: "Road Trips", blurb: "Windows down, volume up.", iconName: "car.fill")
        createCollection(name: "Sunday Morning", blurb: "Gentle starts and Ripples.", iconName: "sun.horizon.fill")
        createCollection(name: "Late Night", blurb: "For after everyone else is asleep.", iconName: "moon.stars.fill")
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
