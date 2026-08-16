import Foundation

nonisolated protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> Data
}

nonisolated enum HTTPError: Error, Equatable {
    case badStatus(Int)
    case invalidResponse
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
                    return data
                case 429, 503:
                    guard attempt < retryDelays.count else { throw HTTPError.badStatus(http.statusCode) }
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
}
