import Foundation
import SwiftData

/// SwiftData-backed cache for archive metadata. MainActor-only.
final class CacheStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = container.mainContext
    }

    // MARK: - Search results

    func cachedSearch(key: String, maxAge: TimeInterval) -> [Show]? {
        let descriptor = FetchDescriptor<CachedShowSearch>(
            predicate: #Predicate { $0.queryKey == key }
        )
        guard let row = try? context.fetch(descriptor).first,
              Date.now.timeIntervalSince(row.fetchedAt) < maxAge,
              let shows = try? JSONDecoder().decode([Show].self, from: row.payload)
        else { return nil }
        return shows
    }

    func storeSearch(key: String, shows: [Show]) {
        guard let payload = try? JSONEncoder().encode(shows) else { return }
        let descriptor = FetchDescriptor<CachedShowSearch>(
            predicate: #Predicate { $0.queryKey == key }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = payload
            existing.fetchedAt = .now
        } else {
            context.insert(CachedShowSearch(queryKey: key, payload: payload))
        }
        try? context.save()
    }

    // MARK: - Recording detail

    func cachedDetail(identifier: String, maxAge: TimeInterval) -> RecordingDetail? {
        let descriptor = FetchDescriptor<CachedRecordingMetadata>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        guard let row = try? context.fetch(descriptor).first,
              Date.now.timeIntervalSince(row.fetchedAt) < maxAge,
              let detail = try? JSONDecoder().decode(RecordingDetail.self, from: row.payload)
        else { return nil }
        return detail
    }

    func storeDetail(_ detail: RecordingDetail) {
        guard let payload = try? JSONEncoder().encode(detail) else { return }
        let id = detail.identifier
        let descriptor = FetchDescriptor<CachedRecordingMetadata>(
            predicate: #Predicate { $0.identifier == id }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = payload
            existing.fetchedAt = .now
        } else {
            context.insert(CachedRecordingMetadata(identifier: id, payload: payload))
        }
        try? context.save()
    }

    func clearAll() {
        try? context.delete(model: CachedShowSearch.self)
        try? context.delete(model: CachedRecordingMetadata.self)
        try? context.save()
    }

    var approximateSizeBytes: Int {
        let searches = (try? context.fetch(FetchDescriptor<CachedShowSearch>())) ?? []
        let details = (try? context.fetch(FetchDescriptor<CachedRecordingMetadata>())) ?? []
        return searches.reduce(0) { $0 + $1.payload.count } + details.reduce(0) { $0 + $1.payload.count }
    }
}
