import Foundation
import Security

// The phone's line to the notesfile (RDVAX::GRATEFUL on the web). One
// bearer token in the Keychain; everything else is JSON over HTTPS.

/// Where the notesfile lives — Info.plist `NetheadURL`, empty means no notesfile.
nonisolated enum NetheadConfig {
    static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "NetheadURL") as? String,
              !raw.isEmpty, let url = URL(string: raw) else { return nil }
        return url
    }
}

/// A place for the session token: the Keychain on device, memory in tests.
nonisolated protocol SecretStore: Sendable {
    func string(for key: String) -> String?
    func set(_ value: String?, for key: String)
}

nonisolated final class KeychainSecretStore: SecretStore, Sendable {
    private let service = "ai.deadheads.notesfile"

    func string(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

nonisolated final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    init() {}
    func string(for key: String) -> String? { lock.withLock { values[key] } }
    func set(_ value: String?, for key: String) { lock.withLock { values[key] = value } }
}

// MARK: - Wire shapes

nonisolated struct NetheadHead: Codable, Sendable, Equatable {
    var id: String
    var handle: String
    var firstShow: String?
}

nonisolated struct PairResponse: Codable, Sendable { var token: String; var head: NetheadHead }
nonisolated struct MeResponse: Codable, Sendable { var head: NetheadHead; var cursor: Int }

nonisolated struct SyncShelf: Codable, Sendable, Equatable {
    var id: String; var name: String; var blurb: String; var iconName: String; var isPrivate: Bool
    var createdAt: String; var updatedAt: String; var deletedAt: String?
}
nonisolated struct SyncShelfItem: Codable, Sendable, Equatable {
    var id: String; var shelfId: String; var showIdentifier: String; var showId: String?; var showDate: String?
    var displayName: String; var sortIndex: Int; var addedAt: String; var updatedAt: String; var deletedAt: String?
}
nonisolated struct SyncMixtape: Codable, Sendable, Equatable {
    var id: String; var name: String; var blurb: String; var iconName: String; var isPrivate: Bool
    var createdAt: String; var updatedAt: String; var deletedAt: String?
}
nonisolated struct SyncMixtapeItem: Codable, Sendable, Equatable {
    var id: String; var mixtapeId: String; var showIdentifier: String; var fileName: String; var trackTitle: String
    var songKey: String; var showDateString: String; var showDisplayName: String; var durationSeconds: Double
    var sortIndex: Int; var addedAt: String; var updatedAt: String; var deletedAt: String?
}
nonisolated struct SyncJournalEntry: Codable, Sendable, Equatable {
    var id: String; var showIdentifier: String; var showId: String?; var showDate: String?; var showDisplayName: String
    var body: String; var mood: String?; var createdAt: String; var updatedAt: String; var deletedAt: String?
}

nonisolated struct SyncBatch: Codable, Sendable, Equatable {
    var shelves: [SyncShelf] = []
    var shelfItems: [SyncShelfItem] = []
    var mixtapes: [SyncMixtape] = []
    var mixtapeItems: [SyncMixtapeItem] = []
    var journalEntries: [SyncJournalEntry] = []

    var isEmpty: Bool {
        shelves.isEmpty && shelfItems.isEmpty && mixtapes.isEmpty && mixtapeItems.isEmpty && journalEntries.isEmpty
    }
    var count: Int { shelves.count + shelfItems.count + mixtapes.count + mixtapeItems.count + journalEntries.count }
}

nonisolated struct SyncPull: Codable, Sendable {
    var cursor: Int
    var shelves: [SyncShelf] = []
    var shelfItems: [SyncShelfItem] = []
    var mixtapes: [SyncMixtape] = []
    var mixtapeItems: [SyncMixtapeItem] = []
    var journalEntries: [SyncJournalEntry] = []
}

nonisolated struct SyncPushResult: Codable, Sendable { var cursor: Int; var accepted: Int; var skipped: Int }

nonisolated struct NoteRow: Codable, Sendable, Identifiable, Hashable {
    var ref: String
    var handle: String?
    var body: String
    var createdAt: String
    var showId: String
    var url: String
    var id: String { ref }
}
nonisolated struct NoteFeed: Codable, Sendable { var noteCount: Int; var page: String; var notes: [NoteRow] }

nonisolated enum NetheadAPIError: Error, Equatable {
    case notConfigured
    /// 401 — the phone's session is gone; pair again from the head's page.
    case notOnTheBus
    case message(String)
    case badResponse(Int)
    case offline
}

/// ISO-8601 with fractional seconds, both ways; the notesfile's clocks are UTC.
nonisolated enum NetheadDates {
    static func string(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().timeZone(separator: .omitted).time(includingFractionalSeconds: true).dateSeparator(.dash))
    }
    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        if let d = try? Date(text, strategy: .iso8601.year().month().day().timeZone(separator: .omitted).time(includingFractionalSeconds: true).dateSeparator(.dash)) { return d }
        if let d = try? Date(text, strategy: .iso8601) { return d }
        if let d = try? Date(text, strategy: .iso8601.year().month().day().dateSeparator(.dash)) { return d }
        return nil
    }
    /// "1977-05-08" for a show date, UTC.
    static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }
}

// MARK: - Client

nonisolated struct NetheadAPIClient: Sendable {
    static let tokenKey = "session-token"

    let baseURL: URL
    let session: URLSession
    let secrets: any SecretStore

    init?(baseURL: URL? = NetheadConfig.baseURL, session: URLSession = .shared, secrets: any SecretStore = KeychainSecretStore()) {
        guard let baseURL else { return nil }
        self.baseURL = baseURL
        self.session = session
        self.secrets = secrets
    }

    var hasToken: Bool { secrets.string(for: Self.tokenKey) != nil }

    /// Where a page lives on the notesfile, for handing off to Safari.
    func url(path: String) -> URL { baseURL.appending(path: path.hasPrefix("/") ? String(path.dropFirst()) : path) }

    func pair(code: String, device: String) async throws -> PairResponse {
        let reply: PairResponse = try await send("POST", "api/pair", body: ["code": code, "device": device], auth: false)
        secrets.set(reply.token, for: Self.tokenKey)
        return reply
    }

    func me() async throws -> MeResponse {
        try await send("GET", "api/me", body: Optional<String>.none, auth: true)
    }

    /// Best effort on the wire, always forgets the token.
    func signOut() async {
        _ = try? await send("POST", "api/signout", body: Optional<String>.none, auth: true) as Empty
        secrets.set(nil, for: Self.tokenKey)
    }

    func forgetToken() { secrets.set(nil, for: Self.tokenKey) }

    func pull(since: Int) async throws -> SyncPull {
        try await send("GET", "api/sync?since=\(since)", body: Optional<String>.none, auth: true)
    }

    func push(_ batch: SyncBatch) async throws -> SyncPushResult {
        try await send("POST", "api/sync", body: batch, auth: true)
    }

    private nonisolated struct SpinBody: Encodable, Sendable { var identifier: String; var showId: String?; var trackTitle: String }

    func spin(identifier: String, showId: String?, trackTitle: String) async {
        _ = try? await send("POST", "api/spin", body: SpinBody(identifier: identifier, showId: showId, trackTitle: trackTitle), auth: true) as Empty
    }

    func stopSpinning() async {
        _ = try? await send("POST", "api/spin", body: ["stopped": true], auth: true) as Empty
    }

    /// The notes under a night. Public.
    func notes(forDate day: String) async throws -> NoteFeed {
        try await send("GET", "api/notes/\(day)", body: Optional<String>.none, auth: false)
    }

    nonisolated struct Empty: Decodable, Sendable {}
    private nonisolated struct ErrorBody: Decodable, Sendable { var error: String }

    private func send<Reply: Decodable, Body: Encodable>(_ method: String, _ path: String, body: Body?, auth: Bool) async throws -> Reply {
        var request = URLRequest(url: baseURL.appending(path: path.split(separator: "?", maxSplits: 1)[0]))
        if let q = path.split(separator: "?", maxSplits: 1).dropFirst().first {
            request.url = URL(string: request.url!.absoluteString + "?" + q)
        }
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Nethead-iOS/1.0", forHTTPHeaderField: "user-agent")
        if auth {
            guard let token = secrets.string(for: Self.tokenKey) else { throw NetheadAPIError.notOnTheBus }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(error.code) {
            throw NetheadAPIError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            if auth { secrets.set(nil, for: Self.tokenKey) }
            throw NetheadAPIError.notOnTheBus
        }
        if status == 204 || (status == 200 && data.isEmpty) {
            if let empty = Empty() as? Reply { return empty }
        }
        if status < 200 || status >= 300 {
            if let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data) { throw NetheadAPIError.message(parsed.error) }
            throw NetheadAPIError.badResponse(status)
        }
        do {
            return try JSONDecoder().decode(Reply.self, from: data)
        } catch {
            throw NetheadAPIError.badResponse(status)
        }
    }
}
