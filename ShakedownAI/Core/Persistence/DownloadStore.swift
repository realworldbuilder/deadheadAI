import Foundation
import Observation
import SwiftData

/// SwiftData index over downloaded audio. MainActor-only. Files on disk are
/// the source of truth for playability; `completedTrackKeys` mirrors them in
/// memory so the streaming decorator can answer synchronously per track.
@Observable
final class DownloadStore {
    nonisolated enum TrackStatus: String { case pending, completed, failed }
    nonisolated enum ShowStatus: String { case queued, downloading, completed, failed }

    /// A ModelContext does not retain its container; if the caller's container
    /// is temporary (tests), fetches trap in SwiftData once it deallocates.
    private let container: ModelContainer
    private let context: ModelContext
    private(set) var completedTrackKeys: Set<String> = []
    /// Bumped on any mutation so list screens can re-fetch.
    private(set) var changeToken = 0

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
        reconcileWithDisk()
    }

    // MARK: - Records

    /// Idempotent: an existing record for the identifier is refreshed with the
    /// latest snapshots instead of duplicated.
    func createRecord(show: Show, detail: RecordingDetail) {
        guard let showPayload = try? JSONEncoder().encode(show),
              let detailPayload = try? JSONEncoder().encode(detail) else { return }
        let record: DownloadedShowRecord
        if let existing = self.record(for: show.identifier) {
            existing.showPayload = showPayload
            existing.detailPayload = detailPayload
            record = existing
        } else {
            record = DownloadedShowRecord(identifier: show.identifier,
                                          showPayload: showPayload,
                                          detailPayload: detailPayload)
            context.insert(record)
        }
        let existingKeys = Set(record.trackRecords.map(\.key))
        for track in detail.tracks {
            let key = DownloadLocations.trackKey(identifier: show.identifier, fileName: track.fileName)
            guard !existingKeys.contains(key) else { continue }
            let row = DownloadedTrackRecord(key: key, fileName: track.fileName)
            row.show = record
            context.insert(row)
        }
        record.statusRaw = ShowStatus.downloading.rawValue
        save()
    }

    func record(for identifier: String) -> DownloadedShowRecord? {
        let descriptor = FetchDescriptor<DownloadedShowRecord>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        return try? context.fetch(descriptor).first
    }

    func allRecords() -> [DownloadedShowRecord] {
        let descriptor = FetchDescriptor<DownloadedShowRecord>(
            sortBy: [SortDescriptor(\.requestedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func showSnapshot(for identifier: String) -> Show? {
        guard let record = record(for: identifier) else { return nil }
        return try? JSONDecoder().decode(Show.self, from: record.showPayload)
    }

    func detailSnapshot(for identifier: String) -> RecordingDetail? {
        guard let record = record(for: identifier) else { return nil }
        return try? JSONDecoder().decode(RecordingDetail.self, from: record.detailPayload)
    }

    // MARK: - Track state

    /// File names still needing a download (pending or failed, or completed
    /// rows whose file has vanished from disk).
    func pendingTracks(for identifier: String) -> [String] {
        guard let record = record(for: identifier) else { return [] }
        return record.trackRecords
            .filter { row in
                if row.statusRaw == TrackStatus.completed.rawValue {
                    return !FileManager.default.fileExists(
                        atPath: DownloadLocations.fileURL(identifier: identifier, fileName: row.fileName).path(percentEncoded: false))
                }
                return true
            }
            .map(\.fileName)
    }

    func markTrackCompleted(identifier: String, fileName: String, bytes: Int64) {
        guard let record = record(for: identifier) else { return }
        let key = DownloadLocations.trackKey(identifier: identifier, fileName: fileName)
        guard let row = record.trackRecords.first(where: { $0.key == key }) else { return }
        row.statusRaw = TrackStatus.completed.rawValue
        row.bytes = bytes
        row.errorText = nil
        completedTrackKeys.insert(key)
        refreshShowStatus(record)
        save()
    }

    func markTrackFailed(identifier: String, fileName: String, error: String) {
        guard let record = record(for: identifier) else { return }
        let key = DownloadLocations.trackKey(identifier: identifier, fileName: fileName)
        guard let row = record.trackRecords.first(where: { $0.key == key }) else { return }
        row.statusRaw = TrackStatus.failed.rawValue
        row.errorText = error
        refreshShowStatus(record)
        save()
    }

    /// Called when a retry re-enqueues tracks, so the show leaves `failed`.
    func markDownloading(identifier: String) {
        guard let record = record(for: identifier) else { return }
        for row in record.trackRecords where row.statusRaw == TrackStatus.failed.rawValue {
            row.statusRaw = TrackStatus.pending.rawValue
            row.errorText = nil
        }
        record.statusRaw = ShowStatus.downloading.rawValue
        record.completedAt = nil
        save()
    }

    // MARK: - Playback lookup

    func localFileURL(identifier: String, fileName: String) -> URL? {
        let key = DownloadLocations.trackKey(identifier: identifier, fileName: fileName)
        guard completedTrackKeys.contains(key) else { return nil }
        let url = DownloadLocations.fileURL(identifier: identifier, fileName: fileName)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            completedTrackKeys.remove(key)
            return nil
        }
        return url
    }

    func isDownloaded(_ identifier: String) -> Bool {
        record(for: identifier)?.statusRaw == ShowStatus.completed.rawValue
    }

    // MARK: - Deletion

    /// Removes the record only — the manager owns task cancellation and file
    /// removal ordering.
    func deleteRecord(identifier: String) {
        guard let record = record(for: identifier) else { return }
        for row in record.trackRecords { completedTrackKeys.remove(row.key) }
        context.delete(record)
        save()
    }

    var totalBytes: Int64 {
        allRecords().reduce(0) { $0 + $1.totalBytes }
    }

    // MARK: - Internals

    /// Heals record/disk disagreement (e.g. files deleted by the system or a
    /// row left `pending` after a crash) and rebuilds the in-memory index.
    private func reconcileWithDisk() {
        var keys: Set<String> = []
        for record in allRecords() {
            for row in record.trackRecords where row.statusRaw == TrackStatus.completed.rawValue {
                let url = DownloadLocations.fileURL(identifier: record.identifier, fileName: row.fileName)
                if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                    keys.insert(row.key)
                } else {
                    row.statusRaw = TrackStatus.pending.rawValue
                    row.bytes = 0
                }
            }
            refreshShowStatus(record)
        }
        completedTrackKeys = keys
        try? context.save()
    }

    private func refreshShowStatus(_ record: DownloadedShowRecord) {
        let rows = record.trackRecords
        record.totalBytes = rows.reduce(0) { $0 + $1.bytes }
        if !rows.isEmpty, rows.allSatisfy({ $0.statusRaw == TrackStatus.completed.rawValue }) {
            record.statusRaw = ShowStatus.completed.rawValue
            if record.completedAt == nil { record.completedAt = .now }
        } else if rows.contains(where: { $0.statusRaw == TrackStatus.pending.rawValue }) {
            // One bad track mustn't flip the whole show to "failed" while the
            // rest are still in flight — failed means every track is settled.
            record.statusRaw = ShowStatus.downloading.rawValue
        } else {
            record.statusRaw = ShowStatus.failed.rawValue
        }
    }

    private func save() {
        try? context.save()
        changeToken += 1
    }
}
