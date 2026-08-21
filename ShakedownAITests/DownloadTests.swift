import Foundation
import SwiftData
import Testing
@testable import ShakedownAI

// MARK: - Fixtures

private func makeShow(identifier: String = "gd1977-05-08.sbd.test") -> Show {
    Show(identifier: identifier, title: "Cornell", date: nil, dateString: "1977-05-08",
         venue: "Barton Hall", location: "Ithaca, NY", year: 1977,
         avgRating: 4.9, numReviews: 100, downloads: nil, source: "SBD")
}

private func makeDetail(identifier: String = "gd1977-05-08.sbd.test",
                        fileNames: [String] = ["d1t01.mp3", "d1t02.mp3", "d1t03.mp3"]) -> RecordingDetail {
    RecordingDetail(identifier: identifier, title: "Cornell", dateString: "1977-05-08",
                    venue: "Barton Hall", location: "Ithaca, NY", source: "SBD",
                    lineage: nil, notes: nil, setlistText: nil,
                    tracks: fileNames.enumerated().map { index, name in
                        Track(fileName: name, title: "Track \(index + 1)",
                              trackNumber: index + 1, durationSeconds: 300)
                    },
                    reviews: [])
}

@MainActor
private func makeStore() -> DownloadStore {
    DownloadStore(container: ModelContainerFactory.make(inMemory: true))
}

// MARK: - Path planning

struct DownloadLocationsTests {
    @Test func fileURLLivesUnderTheShowDirectory() {
        let url = DownloadLocations.fileURL(identifier: "gd77", fileName: "d1t01.mp3")
        #expect(url.path().hasPrefix(DownloadLocations.showDirectory(identifier: "gd77").path()))
        #expect(url.lastPathComponent == "d1t01.mp3")
    }

    @Test func slashesInFileNamesCannotEscapeTheShowDirectory() {
        let url = DownloadLocations.fileURL(identifier: "gd77", fileName: "../../etc/passwd")
        #expect(url.path().hasPrefix(DownloadLocations.showDirectory(identifier: "gd77").path()))
        #expect(!url.path().contains("../"))
    }

    @Test func encodingIsDeterministicAndCollisionFree() {
        // A literal "%2F" in a name must not decode-collide with an encoded "/".
        #expect(DownloadLocations.encode("a/b") != DownloadLocations.encode("a%2Fb"))
        #expect(DownloadLocations.encode("d1t01.mp3") == "d1t01.mp3")
    }

    @Test func taskDescriptionRoundTrips() {
        let description = DownloadLocations.makeTaskDescription(identifier: "gd77.sbd", fileName: "odd|name > weird.mp3")
        let parsed = DownloadLocations.parseTaskDescription(description)
        #expect(parsed?.identifier == "gd77.sbd")
        #expect(parsed?.fileName == "odd|name > weird.mp3")
    }

    @Test func malformedTaskDescriptionsParseAsNil() {
        #expect(DownloadLocations.parseTaskDescription("no-pipe-here") == nil)
        #expect(DownloadLocations.parseTaskDescription("|leading") == nil)
        #expect(DownloadLocations.parseTaskDescription("trailing|") == nil)
    }
}

// MARK: - Store

@MainActor
struct DownloadStoreTests {
    @Test func createRecordTracksEveryFile() {
        let store = makeStore()
        store.createRecord(show: makeShow(), detail: makeDetail())
        let record = store.record(for: makeShow().identifier)
        #expect(record != nil)
        #expect(record?.trackRecords.count == 3)
        #expect(record?.statusRaw == DownloadStore.ShowStatus.downloading.rawValue)
        #expect(store.pendingTracks(for: makeShow().identifier).count == 3)
    }

    @Test func createRecordIsIdempotent() {
        let store = makeStore()
        store.createRecord(show: makeShow(), detail: makeDetail())
        store.createRecord(show: makeShow(), detail: makeDetail())
        #expect(store.allRecords().count == 1)
        #expect(store.record(for: makeShow().identifier)?.trackRecords.count == 3)
    }

    @Test func completingEveryTrackCompletesTheShow() {
        let store = makeStore()
        let show = makeShow()
        store.createRecord(show: show, detail: makeDetail())
        for name in ["d1t01.mp3", "d1t02.mp3", "d1t03.mp3"] {
            store.markTrackCompleted(identifier: show.identifier, fileName: name, bytes: 1000)
        }
        let record = store.record(for: show.identifier)
        #expect(record?.statusRaw == DownloadStore.ShowStatus.completed.rawValue)
        #expect(record?.completedAt != nil)
        #expect(record?.totalBytes == 3000)
        #expect(store.totalBytes == 3000)
    }

    @Test func aFailedTrackOnlyFailsTheShowOnceEveryTrackIsSettled() {
        let store = makeStore()
        let show = makeShow()
        store.createRecord(show: show, detail: makeDetail())
        store.markTrackCompleted(identifier: show.identifier, fileName: "d1t01.mp3", bytes: 1000)
        store.markTrackFailed(identifier: show.identifier, fileName: "d1t02.mp3", error: "boom")
        // d1t03 is still pending — the show is mid-download, not failed.
        #expect(store.record(for: show.identifier)?.statusRaw == DownloadStore.ShowStatus.downloading.rawValue)

        store.markTrackFailed(identifier: show.identifier, fileName: "d1t03.mp3", error: "boom")
        #expect(store.record(for: show.identifier)?.statusRaw == DownloadStore.ShowStatus.failed.rawValue)

        store.markDownloading(identifier: show.identifier)
        let record = store.record(for: show.identifier)
        #expect(record?.statusRaw == DownloadStore.ShowStatus.downloading.rawValue)
        #expect(record?.trackRecords.allSatisfy { $0.errorText == nil } == true)
    }

    @Test func snapshotsRoundTrip() {
        let store = makeStore()
        store.createRecord(show: makeShow(), detail: makeDetail())
        let show = store.showSnapshot(for: makeShow().identifier)
        let detail = store.detailSnapshot(for: makeShow().identifier)
        #expect(show?.venue == "Barton Hall")
        #expect(detail?.tracks.count == 3)
        #expect(detail?.tracks.first?.fileName == "d1t01.mp3")
    }

    @Test func deleteRecordClearsIndexAndRows() {
        let store = makeStore()
        let show = makeShow()
        store.createRecord(show: show, detail: makeDetail())
        store.markTrackCompleted(identifier: show.identifier, fileName: "d1t01.mp3", bytes: 1)
        store.deleteRecord(identifier: show.identifier)
        #expect(store.record(for: show.identifier) == nil)
        #expect(store.completedTrackKeys.isEmpty)
        #expect(store.localFileURL(identifier: show.identifier, fileName: "d1t01.mp3") == nil)
    }

    @Test func localFileURLRequiresARealFileOnDisk() throws {
        let store = makeStore()
        let show = makeShow(identifier: "gd-test-localfile-\(UUID().uuidString)")
        store.createRecord(show: show, detail: makeDetail(identifier: show.identifier, fileNames: ["t.mp3"]))
        store.markTrackCompleted(identifier: show.identifier, fileName: "t.mp3", bytes: 3)
        // Index says completed, but nothing is on disk yet.
        #expect(store.localFileURL(identifier: show.identifier, fileName: "t.mp3") == nil)

        let url = DownloadLocations.fileURL(identifier: show.identifier, fileName: "t.mp3")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: DownloadLocations.showDirectory(identifier: show.identifier)) }

        // Re-mark so the pruned index entry comes back now that the file exists.
        store.markTrackCompleted(identifier: show.identifier, fileName: "t.mp3", bytes: 3)
        #expect(store.localFileURL(identifier: show.identifier, fileName: "t.mp3") == url)
    }
}

// MARK: - Streaming decorator

@MainActor
struct OfflineFirstStreamingProviderTests {
    @Test func fallsThroughWhenNothingIsDownloaded() {
        let store = makeStore()
        let provider = OfflineFirstStreamingProvider(store: store, fallback: MockStreamingProvider())
        let url = provider.streamURL(identifier: "gd77", track: Track(fileName: "t.mp3", title: "T",
                                                                      trackNumber: 1, durationSeconds: 60))
        #expect(url?.host() == "example.com")
    }

    @Test func prefersTheLocalFileWhenDownloaded() throws {
        let store = makeStore()
        let show = makeShow(identifier: "gd-test-decorator-\(UUID().uuidString)")
        store.createRecord(show: show, detail: makeDetail(identifier: show.identifier, fileNames: ["t.mp3"]))

        let url = DownloadLocations.fileURL(identifier: show.identifier, fileName: "t.mp3")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: DownloadLocations.showDirectory(identifier: show.identifier)) }
        store.markTrackCompleted(identifier: show.identifier, fileName: "t.mp3", bytes: 3)

        let provider = OfflineFirstStreamingProvider(store: store, fallback: MockStreamingProvider())
        let resolved = provider.streamURL(identifier: show.identifier,
                                          track: Track(fileName: "t.mp3", title: "T",
                                                       trackNumber: 1, durationSeconds: 60))
        #expect(resolved?.isFileURL == true)
        #expect(resolved == url)
    }
}

// MARK: - Manager display state

@MainActor
struct DownloadManagerTests {
    private func makeManager() -> DownloadManager {
        DownloadManager(container: ModelContainerFactory.make(inMemory: true),
                        makeSession: { _ in URLSession(configuration: .ephemeral) })
    }

    @Test func progressFractionBlendsTracksAndBytes() {
        let progress = DownloadManager.ShowProgress(completedTracks: 2, totalTracks: 4, currentTrackFraction: 0.5)
        #expect(progress.fraction == 0.625)
        #expect(DownloadManager.ShowProgress(completedTracks: 0, totalTracks: 0, currentTrackFraction: 0).fraction == 0)
        // Fractions clamp: a server reporting weird byte counts can't push past 100%.
        let over = DownloadManager.ShowProgress(completedTracks: 3, totalTracks: 4, currentTrackFraction: 1.7)
        #expect(over.fraction == 1.0)
    }

    @Test func displayStateReflectsTheStore() {
        let manager = makeManager()
        let show = makeShow()
        #expect(manager.displayState(for: show.identifier) == .notDownloaded)

        manager.store.createRecord(show: show, detail: makeDetail())
        guard case .inProgress(let progress) = manager.displayState(for: show.identifier) else {
            Issue.record("expected inProgress")
            return
        }
        #expect(progress.totalTracks == 3)
        #expect(progress.completedTracks == 0)

        for name in ["d1t01.mp3", "d1t02.mp3", "d1t03.mp3"] {
            manager.store.markTrackCompleted(identifier: show.identifier, fileName: name, bytes: 10)
        }
        #expect(manager.displayState(for: show.identifier) == .downloaded(bytes: 30))

        manager.store.markTrackFailed(identifier: show.identifier, fileName: "d1t02.mp3", error: "boom")
        #expect(manager.displayState(for: show.identifier) == .failed(completedTracks: 2, totalTracks: 3))
    }
}
