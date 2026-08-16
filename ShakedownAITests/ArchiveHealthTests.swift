import Foundation
import Testing
@testable import ShakedownAI

/// Always answers 503, like archive.org during an outage.
nonisolated final class Stub503Protocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 503,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct ArchiveHealthTests {

    @Test func exhausted503BecomesServiceUnavailable() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub503Protocol.self]
        let client = URLSessionHTTPClient(session: URLSession(configuration: config),
                                          retryDelays: [])
        await #expect(throws: HTTPError.serviceUnavailable) {
            _ = try await client.get(URL(string: "https://archive.org/advancedsearch.php")!)
        }
    }

    @Test func outageFlipsStateAndRecoveryClears() {
        let health = ArchiveHealth()
        #expect(!health.isOffline)
        health.reportOutage()
        #expect(health.isOffline)
        health.reportSuccess()
        #expect(!health.isOffline)
    }

    @Test func successWhileHealthyIsANoop() {
        let health = ArchiveHealth()
        health.reportSuccess()
        #expect(!health.isOffline)
    }
}
