import Foundation
import SwiftData
import Testing
@testable import ShakedownAI

// MARK: - Container partition

struct ContainerPartitionTests {
    @Test func everyModelHasAHomeAndRoundTrips() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext

        let collection = ShowCollection(name: "Favorites")
        context.insert(collection)
        let item = CollectionItem(showIdentifier: "gd1977-05-08", showDate: nil,
                                  displayName: "Cornell", sortIndex: 0)
        item.collection = collection
        context.insert(item)
        context.insert(JournalEntry(showIdentifier: "gd1977-05-08", showDate: nil,
                                    showDisplayName: "Cornell", body: "Wow"))
        context.insert(CachedShowSearch(queryKey: "q", payload: Data()))
        context.insert(CachedRecordingMetadata(identifier: "gd1977-05-08", payload: Data()))
        context.insert(SmartCollectionRecord(slotID: "daypart", payload: Data(),
                                             contextKey: "k", generatedAt: .now, sortIndex: 0))
        context.insert(ListeningEvent(showIdentifier: "gd1977-05-08", showDisplayName: "Cornell",
                                      trackTitle: "Scarlet Begonias", songKey: "scarlet begonias",
                                      showYear: 1977, venue: "Barton Hall"))
        context.insert(TasteProfileRecord(payload: Data()))
        context.insert(JourneyState(journeyID: "primal"))
        let thread = ChatThread(title: "hey now")
        context.insert(thread)
        context.insert(LocalAccount(displayName: "Deadhead"))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ShowCollection>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ListeningEvent>()).count == 1)
        let fetched = try #require(try context.fetch(FetchDescriptor<ShowCollection>()).first)
        #expect((fetched.items ?? []).count == 1)
    }
}

// MARK: - Migration

struct CloudStoreMigrationTests {
    private func tempStoreURL(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "cloud-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: name)
    }

    private func populateLegacyStore(at url: URL) throws {
        let schema = Schema(ModelContainerFactory.allModels)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let favorites = ShowCollection(name: "Favorites", blurb: "The ones that got you.")
        context.insert(favorites)
        for (index, id) in ["gd1977-05-08", "gd1969-02-27"].enumerated() {
            let item = CollectionItem(showIdentifier: id, showDate: nil,
                                      displayName: id, sortIndex: index)
            item.collection = favorites
            context.insert(item)
        }
        let roadTrips = ShowCollection(name: "Road Trips")
        context.insert(roadTrips)
        let solo = CollectionItem(showIdentifier: "gd1972-05-11", showDate: nil,
                                  displayName: "Rotterdam", sortIndex: 0)
        solo.collection = roadTrips
        context.insert(solo)

        context.insert(JournalEntry(showIdentifier: "gd1977-05-08", showDate: nil,
                                    showDisplayName: "Cornell", body: "First listen."))
        context.insert(JournalEntry(showIdentifier: "gd1969-02-27", showDate: nil,
                                    showDisplayName: "Fillmore West", body: "That Dark Star.", mood: "cosmic"))
        try context.save()
    }

    @Test func migrationCopiesCollectionsAndJournal() throws {
        let sourceURL = try tempStoreURL("legacy.store")
        let targetURL = try tempStoreURL("cloud.store")
        try populateLegacyStore(at: sourceURL)

        try CloudStoreMigrator.migrate(from: sourceURL, to: targetURL)

        let schema = Schema(ModelContainerFactory.cloudModels)
        let config = ModelConfiguration(schema: schema, url: targetURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let collections = try context.fetch(FetchDescriptor<ShowCollection>())
        #expect(collections.count == 2)
        let favorites = try #require(collections.first { $0.name == "Favorites" })
        #expect((favorites.items ?? []).count == 2)
        #expect(favorites.blurb == "The ones that got you.")

        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 2)
        #expect(entries.contains { $0.mood == "cosmic" })
    }

    @Test func migrationIsIdempotent() throws {
        let sourceURL = try tempStoreURL("legacy.store")
        let targetURL = try tempStoreURL("cloud.store")
        try populateLegacyStore(at: sourceURL)

        try CloudStoreMigrator.migrate(from: sourceURL, to: targetURL)
        try CloudStoreMigrator.migrate(from: sourceURL, to: targetURL)

        let schema = Schema(ModelContainerFactory.cloudModels)
        let config = ModelConfiguration(schema: schema, url: targetURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        #expect(try container.mainContext.fetch(FetchDescriptor<ShowCollection>()).count == 2)
        #expect(try container.mainContext.fetch(FetchDescriptor<CollectionItem>()).count == 3)
        #expect(try container.mainContext.fetch(FetchDescriptor<JournalEntry>()).count == 2)
    }

    @Test func freshInstallJustSetsTheFlag() throws {
        let suite = "migration-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let missing = try tempStoreURL("never-created.store")
        let target = try tempStoreURL("cloud.store")

        CloudStoreMigrator.migrateIfNeeded(legacyURL: missing, cloudURL: target, defaults: defaults)

        #expect(defaults.bool(forKey: CloudStoreMigrator.flagKey))
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test func completedMigrationDoesNotRunAgain() throws {
        let suite = "migration-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sourceURL = try tempStoreURL("legacy.store")
        let targetURL = try tempStoreURL("cloud.store")
        try populateLegacyStore(at: sourceURL)
        defaults.set(true, forKey: CloudStoreMigrator.flagKey)

        CloudStoreMigrator.migrateIfNeeded(legacyURL: sourceURL, cloudURL: targetURL, defaults: defaults)

        #expect(!FileManager.default.fileExists(atPath: targetURL.path))
    }
}

// MARK: - Dedup

struct LibraryDedupTests {
    // The container must outlive the test body — a context whose container
    // deallocates traps on first use.
    private func makeStore() -> (LibraryStore, ModelContext, ModelContainer) {
        let container = ModelContainerFactory.make(inMemory: true)
        return (LibraryStore(container: container), container.mainContext, container)
    }

    @Test func duplicateSeedShelvesCollapseAndMergeItems() throws {
        let (store, context, container) = makeStore()
        _ = container
        let older = ShowCollection(name: "Favorites")
        older.createdAt = Date(timeIntervalSince1970: 100)
        context.insert(older)
        let cornell = CollectionItem(showIdentifier: "gd1977-05-08", showDate: nil,
                                     displayName: "Cornell", sortIndex: 0)
        cornell.collection = older
        context.insert(cornell)

        let newer = ShowCollection(name: "Favorites")
        newer.createdAt = Date(timeIntervalSince1970: 200)
        context.insert(newer)
        let cornellDupe = CollectionItem(showIdentifier: "gd1977-05-08", showDate: nil,
                                         displayName: "Cornell", sortIndex: 0)
        cornellDupe.collection = newer
        context.insert(cornellDupe)
        let veneta = CollectionItem(showIdentifier: "gd1972-08-27", showDate: nil,
                                    displayName: "Veneta", sortIndex: 1)
        veneta.collection = newer
        context.insert(veneta)
        try context.save()

        store.dedupAfterSync()

        let survivors = try context.fetch(FetchDescriptor<ShowCollection>())
        #expect(survivors.count == 1)
        let favorites = try #require(survivors.first)
        #expect(favorites.createdAt == Date(timeIntervalSince1970: 100))
        let items = (favorites.items ?? []).sorted { $0.sortIndex < $1.sortIndex }
        #expect(items.map(\.showIdentifier) == ["gd1977-05-08", "gd1972-08-27"])
        #expect(items.map(\.sortIndex) == [0, 1])
    }

    @Test func duplicateCollectionIDsCollapseDeterministically() throws {
        let (store, context, container) = makeStore()
        _ = container
        let sharedID = UUID()
        let a = ShowCollection(name: "Tour Tapes")
        a.id = sharedID
        a.createdAt = Date(timeIntervalSince1970: 100)
        context.insert(a)
        let b = ShowCollection(name: "Tour Tapes")
        b.id = sharedID
        b.createdAt = Date(timeIntervalSince1970: 50)
        context.insert(b)
        try context.save()

        store.dedupAfterSync()

        let survivors = try context.fetch(FetchDescriptor<ShowCollection>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.createdAt == Date(timeIntervalSince1970: 50))
    }

    @Test func duplicateJournalEntriesKeepTheLatestEdit() throws {
        let (store, context, container) = makeStore()
        _ = container
        let sharedID = UUID()
        let stale = JournalEntry(showIdentifier: "gd1977-05-08", showDate: nil,
                                 showDisplayName: "Cornell", body: "Draft")
        stale.id = sharedID
        stale.updatedAt = Date(timeIntervalSince1970: 100)
        context.insert(stale)
        let fresh = JournalEntry(showIdentifier: "gd1977-05-08", showDate: nil,
                                 showDisplayName: "Cornell", body: "Final thoughts")
        fresh.id = sharedID
        fresh.updatedAt = Date(timeIntervalSince1970: 200)
        context.insert(fresh)
        try context.save()

        store.dedupAfterSync()

        let entries = try context.fetch(FetchDescriptor<JournalEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.body == "Final thoughts")
    }
}

// MARK: - The notesfile account

/// Answers the notesfile's few calls from memory, so the provider can be
/// exercised with no network.
nonisolated final class NotesfileStubProtocol: URLProtocol {
    nonisolated(unsafe) static var meStatus = 200
    nonisolated(unsafe) static var lastPath = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lastPath = path
        var status = 200
        var body = "{}"
        switch path {
        case "/api/pair":
            body = #"{"token":"tok-123","head":{"id":"H1","handle":"SHAKEDOWN::OG","firstShow":"1987-11-18"}}"#
        case "/api/me":
            status = Self.meStatus
            body = status == 200 ? #"{"head":{"id":"H1","handle":"SHAKEDOWN::OG","firstShow":"1987-11-18"},"cursor":4}"# : #"{"error":"Not on the bus."}"#
        case "/api/signout":
            status = 204
            body = ""
        default:
            status = 404
            body = #"{"error":"nope"}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

struct NetheadAuthProviderTests {
    private func make() throws -> (NetheadAuthProvider, UserDefaults, String, InMemorySecretStore) {
        let suite = "auth-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NotesfileStubProtocol.self]
        let secrets = InMemorySecretStore()
        let api = try #require(NetheadAPIClient(baseURL: URL(string: "https://nethead.test")!,
                                                session: URLSession(configuration: config), secrets: secrets))
        return (NetheadAuthProvider(api: api, defaults: defaults), defaults, suite, secrets)
    }

    @Test func pairingRemembersTheHandleAndTheToken() async throws {
        let (provider, defaults, suite, secrets) = try make()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(provider.currentAccount == nil)
        let account = try await provider.pair(code: "rose-77")
        #expect(account.handle == "SHAKEDOWN::OG")
        #expect(account.firstShow == "1987-11-18")
        #expect(secrets.string(for: NetheadAPIClient.tokenKey) == "tok-123")
        // a relaunch with the same defaults and Keychain still knows the head
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NotesfileStubProtocol.self]
        let again = NetheadAuthProvider(api: NetheadAPIClient(baseURL: URL(string: "https://nethead.test")!,
                                                              session: URLSession(configuration: config), secrets: secrets),
                                        defaults: defaults)
        #expect(again.currentAccount == account)
        // no token means no account, whatever the defaults say
        let bare = NetheadAuthProvider(api: NetheadAPIClient(baseURL: URL(string: "https://nethead.test")!,
                                                             session: URLSession(configuration: config), secrets: InMemorySecretStore()),
                                       defaults: defaults)
        #expect(bare.currentAccount == nil)
    }

    @Test func signOutForgetsEverything() async throws {
        let (provider, defaults, suite, secrets) = try make()
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = try await provider.pair(code: "rose-77")
        await provider.signOut()
        #expect(provider.currentAccount == nil)
        #expect(secrets.string(for: NetheadAPIClient.tokenKey) == nil)
        #expect(NetheadAuthProvider.persistedAccount(in: defaults) == nil)
    }

    @Test func aDeadSessionSignsOutOnRefresh() async throws {
        let (provider, defaults, suite, _) = try make()
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = try await provider.pair(code: "rose-77")
        NotesfileStubProtocol.meStatus = 200
        await provider.refresh()
        #expect(provider.currentAccount?.handle == "SHAKEDOWN::OG")
        NotesfileStubProtocol.meStatus = 401
        await provider.refresh()
        NotesfileStubProtocol.meStatus = 200
        #expect(provider.currentAccount == nil)
    }
}
