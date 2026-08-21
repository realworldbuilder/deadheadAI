import Foundation
import OSLog

/// The nonisolated edge of the background download session. Owns the one job
/// that must happen synchronously off-main — moving the finished temp file
/// into place before `didFinishDownloadingTo` returns (the system deletes it
/// after that) — and reports everything else upward through Sendable closures
/// that hop to the MainActor DownloadManager.
nonisolated final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let onProgress: @Sendable (_ identifier: String, _ fileName: String,
                               _ written: Int64, _ expected: Int64) -> Void
    let onFinished: @Sendable (_ identifier: String, _ fileName: String,
                               _ result: Result<Int64, any Error>) -> Void
    let onBackgroundEventsComplete: @Sendable () -> Void

    init(onProgress: @escaping @Sendable (String, String, Int64, Int64) -> Void,
         onFinished: @escaping @Sendable (String, String, Result<Int64, any Error>) -> Void,
         onBackgroundEventsComplete: @escaping @Sendable () -> Void) {
        self.onProgress = onProgress
        self.onFinished = onFinished
        self.onBackgroundEventsComplete = onBackgroundEventsComplete
    }

    nonisolated struct HTTPStatusError: Error, LocalizedError {
        let statusCode: Int
        var errorDescription: String? { "The archive answered \(statusCode)." }
    }

    private static let log = Logger(subsystem: "ai.deadheads", category: "downloads")

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let description = downloadTask.taskDescription,
              let (identifier, fileName) = DownloadLocations.parseTaskDescription(description) else { return }

        // A download task "succeeds" even when the server sends an error page —
        // never keep a non-2xx body.
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            onFinished(identifier, fileName, .failure(HTTPStatusError(statusCode: http.statusCode)))
            return
        }

        do {
            let destination = DownloadLocations.fileURL(identifier: identifier, fileName: fileName)
            let directory = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            DownloadLocations.excludeFromBackup(DownloadLocations.root)
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))
            let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            onFinished(identifier, fileName, .success(bytes))
        } catch {
            onFinished(identifier, fileName, .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: (any Error)?) {
        // Success already reported from didFinishDownloadingTo; explicit
        // cancellation isn't a failure (the manager deleted the record).
        guard let error, (error as? URLError)?.code != .cancelled,
              let description = task.taskDescription,
              let (identifier, fileName) = DownloadLocations.parseTaskDescription(description) else { return }
        Self.log.error("Download failed for \(description, privacy: .public): \(String(describing: error), privacy: .public)")
        onFinished(identifier, fileName, .failure(error))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let description = downloadTask.taskDescription,
              let (identifier, fileName) = DownloadLocations.parseTaskDescription(description) else { return }
        onProgress(identifier, fileName, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        onBackgroundEventsComplete()
    }
}
