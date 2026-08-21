import Foundation
import Observation
import SwiftData

/// MainActor façade over the background download session. UI reads
/// `displayState(for:)` and `progressByShow`; the store holds durable state.
@Observable
final class DownloadManager {
    nonisolated struct ShowProgress: Sendable, Equatable {
        var completedTracks: Int
        var totalTracks: Int
        var currentTrackFraction: Double

        var fraction: Double {
            guard totalTracks > 0 else { return 0 }
            return (Double(completedTracks) + min(max(currentTrackFraction, 0), 1)) / Double(totalTracks)
        }
    }

    enum DisplayState: Equatable {
        case notDownloaded
        case inProgress(ShowProgress)
        case downloaded(bytes: Int64)
        case failed(completedTracks: Int, totalTracks: Int)
    }

    static let sessionIdentifier = "ai.deadheads.downloads"
    static let wifiOnlyDefaultsKey = "downloadsWifiOnly"

    /// Creating two background sessions with one identifier is an error, and
    /// sign-in/out rebuilds the whole AppEnvironment — so the live session is
    /// process-global and reused; only its delegate's target manager moves.
    private static var cachedSession: URLSession?
    private static let delegateBox = DelegateBox()

    /// Routes delegate callbacks to the newest manager instance.
    private final class DelegateBox {
        weak var manager: DownloadManager?
    }

    let store: DownloadStore
    private(set) var progressByShow: [String: ShowProgress] = [:]
    private var session: URLSession!
    private var lastProgressUpdate: [String: Date] = [:]

    var wifiOnly: Bool {
        didSet { UserDefaults.standard.set(wifiOnly, forKey: Self.wifiOnlyDefaultsKey) }
    }

    init(container: ModelContainer,
         makeSession: ((DownloadSessionDelegate) -> URLSession)? = nil) {
        self.store = DownloadStore(container: container)
        self.wifiOnly = UserDefaults.standard.object(forKey: Self.wifiOnlyDefaultsKey) as? Bool ?? true
        Self.delegateBox.manager = self

        let box = Self.delegateBox
        let delegate = DownloadSessionDelegate(
            onProgress: { identifier, fileName, written, expected in
                Task { @MainActor in
                    box.manager?.handleProgress(identifier: identifier, fileName: fileName,
                                                written: written, expected: expected)
                }
            },
            onFinished: { identifier, fileName, result in
                Task { @MainActor in
                    box.manager?.handleFinished(identifier: identifier, fileName: fileName, result: result)
                }
            },
            onBackgroundEventsComplete: {
                Task { @MainActor in
                    AppDelegate.backgroundSessionCompletionHandler?()
                    AppDelegate.backgroundSessionCompletionHandler = nil
                }
            }
        )

        if let makeSession {
            self.session = makeSession(delegate)
        } else if let cached = Self.cachedSession {
            self.session = cached
        } else {
            let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
            config.isDiscretionary = false
            config.sessionSendsLaunchEvents = true
            config.httpMaximumConnectionsPerHost = 2
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            Self.cachedSession = session
            self.session = session
        }
    }

    // MARK: - Queries

    func displayState(for identifier: String) -> DisplayState {
        guard let record = store.record(for: identifier) else { return .notDownloaded }
        switch DownloadStore.ShowStatus(rawValue: record.statusRaw) {
        case .completed:
            return .downloaded(bytes: record.totalBytes)
        case .failed:
            let done = record.trackRecords.filter { $0.statusRaw == DownloadStore.TrackStatus.completed.rawValue }.count
            return .failed(completedTracks: done, totalTracks: record.trackRecords.count)
        default:
            return .inProgress(progressByShow[identifier]
                ?? currentProgress(identifier: identifier, currentTrackFraction: 0))
        }
    }

    // MARK: - Commands

    func download(show: Show, detail: RecordingDetail) {
        store.createRecord(show: show, detail: detail)
        // Re-downloading a partly-failed show is a retry: reset stale failed
        // rows so they re-enqueue and the status reflects the fresh attempt.
        store.markDownloading(identifier: show.identifier)
        enqueuePending(identifier: show.identifier)
    }

    func retry(identifier: String) {
        store.markDownloading(identifier: identifier)
        enqueuePending(identifier: identifier)
    }

    func cancelAndDelete(identifier: String) {
        progressByShow[identifier] = nil
        session.getAllTasks { tasks in
            let matching = tasks.filter {
                DownloadLocations.parseTaskDescription($0.taskDescription ?? "")?.identifier == identifier
            }
            for task in matching { task.cancel() }
            Task { @MainActor in
                try? FileManager.default.removeItem(at: DownloadLocations.showDirectory(identifier: identifier))
                Self.delegateBox.manager?.store.deleteRecord(identifier: identifier)
            }
        }
    }

    func deleteAllDownloads() {
        let identifiers = store.allRecords().map(\.identifier)
        for identifier in identifiers { cancelAndDelete(identifier: identifier) }
    }

    /// Rebinds live background tasks after a relaunch and re-enqueues shows the
    /// records say are mid-download but the session has forgotten (app killed
    /// after the session gave up, disk edits, etc.). Idempotent per track.
    func reconcileOnLaunch() {
        session.getAllTasks { tasks in
            let liveIdentifiers = Set(tasks.compactMap {
                DownloadLocations.parseTaskDescription($0.taskDescription ?? "")?.identifier
            })
            Task { @MainActor in
                guard let manager = Self.delegateBox.manager else { return }
                for record in manager.store.allRecords()
                where record.statusRaw == DownloadStore.ShowStatus.downloading.rawValue {
                    if liveIdentifiers.contains(record.identifier) {
                        manager.progressByShow[record.identifier] =
                            manager.currentProgress(identifier: record.identifier, currentTrackFraction: 0)
                    } else {
                        manager.enqueuePending(identifier: record.identifier)
                    }
                }
            }
        }
    }

    // MARK: - Internals

    private func enqueuePending(identifier: String) {
        let fileNames = store.pendingTracks(for: identifier)
        guard !fileNames.isEmpty else { return }
        progressByShow[identifier] = currentProgress(identifier: identifier, currentTrackFraction: 0)
        for fileName in fileNames {
            guard let url = ArchiveAPIClient.streamURL(identifier: identifier, fileName: fileName) else {
                store.markTrackFailed(identifier: identifier, fileName: fileName,
                                      error: "Couldn't build a download URL.")
                continue
            }
            var request = URLRequest(url: url)
            request.setValue("ShakedownAI/1.0 (iOS; Grateful Dead companion)", forHTTPHeaderField: "User-Agent")
            request.allowsCellularAccess = !wifiOnly
            request.allowsExpensiveNetworkAccess = !wifiOnly
            let task = session.downloadTask(with: request)
            task.taskDescription = DownloadLocations.makeTaskDescription(identifier: identifier, fileName: fileName)
            task.resume()
        }
    }

    private func handleProgress(identifier: String, fileName: String, written: Int64, expected: Int64) {
        // Throttle: UI-only state, no need for every 64KB tick.
        let now = Date.now
        if let last = lastProgressUpdate[identifier], now.timeIntervalSince(last) < 0.3 { return }
        lastProgressUpdate[identifier] = now
        let fraction = expected > 0 ? Double(written) / Double(expected) : 0
        progressByShow[identifier] = currentProgress(identifier: identifier, currentTrackFraction: fraction)
    }

    private func handleFinished(identifier: String, fileName: String, result: Result<Int64, any Error>) {
        // Deleted mid-flight? Discard the orphan file and move on.
        guard store.record(for: identifier) != nil else {
            try? FileManager.default.removeItem(
                at: DownloadLocations.fileURL(identifier: identifier, fileName: fileName))
            return
        }
        switch result {
        case .success(let bytes):
            store.markTrackCompleted(identifier: identifier, fileName: fileName, bytes: bytes)
        case .failure(let error):
            store.markTrackFailed(identifier: identifier, fileName: fileName,
                                  error: error.localizedDescription)
        }
        if store.record(for: identifier)?.statusRaw == DownloadStore.ShowStatus.downloading.rawValue {
            progressByShow[identifier] = currentProgress(identifier: identifier, currentTrackFraction: 0)
        } else {
            progressByShow[identifier] = nil
            lastProgressUpdate[identifier] = nil
        }
    }

    private func currentProgress(identifier: String, currentTrackFraction: Double) -> ShowProgress {
        let rows = store.record(for: identifier)?.trackRecords ?? []
        let done = rows.filter { $0.statusRaw == DownloadStore.TrackStatus.completed.rawValue }.count
        return ShowProgress(completedTracks: done, totalTracks: rows.count,
                            currentTrackFraction: currentTrackFraction)
    }
}
