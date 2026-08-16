import Foundation

nonisolated protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> Data
}

nonisolated enum HTTPError: Error, Equatable {
    case badStatus(Int)
    case invalidResponse
    /// 429/503 that survived every retry — the service is down or overloaded,
    /// as opposed to the device being offline.
    case serviceUnavailable
}

/// URLSession-backed client with polite retry on 429/503 (archive.org 503s under load).
nonisolated final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let retryDelays: [Duration]

    init(session: URLSession = .shared, retryDelays: [Duration] = [.milliseconds(500), .seconds(2)]) {
        self.session = session
        self.retryDelays = retryDelays
    }

    func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("ShakedownAI/1.0 (iOS; Grateful Dead companion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
                switch http.statusCode {
                case 200...299:
                    reportArchiveHealth(url: url, healthy: true)
                    return data
                case 429, 503:
                    guard attempt < retryDelays.count else {
                        reportArchiveHealth(url: url, healthy: false)
                        throw HTTPError.serviceUnavailable
                    }
                    try await Task.sleep(for: retryDelays[attempt])
                    attempt += 1
                default:
                    throw HTTPError.badStatus(http.statusCode)
                }
            } catch let error as HTTPError {
                throw error
            } catch {
                guard attempt < retryDelays.count else { throw error }
                try await Task.sleep(for: retryDelays[attempt])
                attempt += 1
            }
        }
    }

    /// Server-side outages flip the app-wide banner; only archive.org counts.
    private func reportArchiveHealth(url: URL, healthy: Bool) {
        guard url.host()?.hasSuffix("archive.org") == true else { return }
        Task { @MainActor in
            healthy ? ArchiveHealth.shared.reportSuccess() : ArchiveHealth.shared.reportOutage()
        }
    }
}
