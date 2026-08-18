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

// MARK: - AI gate

struct AIGateTests {
    @Test func gateTruthTable() {
        #expect(KeychainStore.resolveAPIKey(bundled: "sk-test", unlocked: true) == "sk-test")
        #expect(KeychainStore.resolveAPIKey(bundled: "sk-test", unlocked: false) == nil)
        #expect(KeychainStore.resolveAPIKey(bundled: nil, unlocked: true) == nil)
        #expect(KeychainStore.resolveAPIKey(bundled: nil, unlocked: false) == nil)
    }
}

// MARK: - Persistent auth

struct PersistentAuthProviderTests {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "auth-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    @Test func appleAccountSurvivesRelaunch() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = PersistentAuthProvider(defaults: defaults)
        _ = try await first.signInWithApple(userID: "apple-123", displayName: "Jerry")

        let second = PersistentAuthProvider(defaults: defaults)
        #expect(second.currentAccount == UserAccount(displayName: "Jerry", appleUserID: "apple-123"))
        #expect(PersistentAuthProvider.persistedAppleUserID(in: defaults) == "apple-123")
    }

    @Test func localAccountDoesNotEnableSync() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let provider = PersistentAuthProvider(defaults: defaults)
        _ = try await provider.signInLocally(displayName: "Deadhead")

        #expect(PersistentAuthProvider.persistedAppleUserID(in: defaults) == nil)
        #expect(PersistentAuthProvider(defaults: defaults).currentAccount?.displayName == "Deadhead")
    }

    @Test func signOutClearsAccountAndAIUnlock() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let provider = PersistentAuthProvider(defaults: defaults)
        _ = try await provider.signInWithApple(userID: "apple-123", displayName: "Jerry")
        KeychainStore.unlockAI()
        await provider.signOut()

        #expect(provider.currentAccount == nil)
        #expect(PersistentAuthProvider.persistedAppleUserID(in: defaults) == nil)
        #expect(!UserDefaults.standard.bool(forKey: "aiAccessUnlocked"))
    }
}
