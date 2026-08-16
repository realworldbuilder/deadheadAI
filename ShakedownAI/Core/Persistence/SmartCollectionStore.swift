import Foundation
import SwiftData

/// Caches generated shelves so they survive relaunches and don't regenerate on
/// every appearance. Shared across screens: Home and Library read the same rows.
@Observable
final class SmartCollectionStore {
    private let context: ModelContext

    private(set) var collections: [SmartCollection] = []
    private(set) var isRefreshing = false
    /// The `DayContext.key` the cached shelves were built for.
    private(set) var contextKey: String = ""

    init(container: ModelContainer) {
        self.context = container.mainContext
        load()
    }

    var lastGenerated: Date? {
        collections.map(\.generatedAt).max()
    }

    func load() {
        let descriptor = FetchDescriptor<SmartCollectionRecord>(sortBy: [SortDescriptor(\.sortIndex)])
        let records = (try? context.fetch(descriptor)) ?? []
        collections = records.compactMap { try? JSONDecoder().decode(SmartCollection.self, from: $0.payload) }
        contextKey = records.first?.contextKey ?? ""
    }

    func needsRefresh(for key: String) -> Bool {
        collections.isEmpty || contextKey != key
    }

    /// Claims the refresh slot; returns false when another screen is already on it.
    func beginRefresh() -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        return true
    }

    func endRefresh() {
        isRefreshing = false
    }

    func replace(with collections: [SmartCollection], contextKey: String) {
        let existing = (try? context.fetch(FetchDescriptor<SmartCollectionRecord>())) ?? []
        for record in existing { context.delete(record) }
        for (index, collection) in collections.enumerated() {
            guard let payload = try? JSONEncoder().encode(collection) else { continue }
            context.insert(SmartCollectionRecord(slotID: collection.slotID,
                                                 payload: payload,
                                                 contextKey: contextKey,
                                                 generatedAt: collection.generatedAt,
                                                 sortIndex: index))
        }
        try? context.save()
        self.collections = collections
        self.contextKey = contextKey
    }

    func collection(slotID: String) -> SmartCollection? {
        collections.first { $0.slotID == slotID }
    }
}
