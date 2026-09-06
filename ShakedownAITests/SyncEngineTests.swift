import Foundation
import SwiftData
import Testing
@testable import ShakedownAI

/// Stands in for the notesfile: remembers what was pushed, answers pulls with what it's told.
final class MockSyncTransport: SyncTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _pushed: [SyncBatch] = []
    private var _pull = SyncPull(cursor: 0)
    private var _fail: NetheadAPIError?

    var pushed: [SyncBatch] { lock.withLock { _pushed } }
    func answerPulls(with pull: SyncPull) { lock.withLock { _pull = pull } }
    func fail(with error: NetheadAPIError?) { lock.withLock { _fail = error } }

    func pull(since: Int) async throws -> SyncPull {
        if let e = lock.withLock({ _fail }) { throw e }
        return lock.withLock { _pull }
    }

    func push(_ batch: SyncBatch) async throws -> SyncPushResult {
        if let e = lock.withLock({ _fail }) { throw e }
        lock.withLock { _pushed.append(batch) }
        return SyncPushResult(cursor: 10, accepted: batch.count, skipped: 0)
    }
}

@MainActor
struct SyncEngineTests {
    /// Everything a test needs, with the container held so SwiftData keeps its contexts alive.
    private struct Rig {
        let container: ModelContainer
        let engine: SyncEngine
        let library: LibraryStore
        let transport: MockSyncTransport
        let auth: MockAuthProvider
        var context: ModelContext { container.mainContext }
    }

    private func make() throws -> Rig {
        let container = ModelContainerFactory.make(inMemory: true)
        let library = LibraryStore(container: container)
        let transport = MockSyncTransport()
        let auth = MockAuthProvider()
        let defaults = try #require(UserDefaults(suiteName: "sync-test-\(UUID().uuidString)"))
        let engine = SyncEngine(container: container, library: library, transport: transport, auth: auth, defaults: defaults)
        return Rig(container: container, engine: engine, library: library, transport: transport, auth: auth)
    }

    private let cornell = Show(identifier: "gd77-05-08.sbd.hicks.4982.sbeok.shnf", title: "Cornell",
                               date: Date(timeIntervalSince1970: 231897600), dateString: "1977-05-08",
                               venue: "Barton Hall", location: "Ithaca, NY", year: 1977,
                               avgRating: 4.8, numReviews: 300, downloads: 1000, source: "SBD")

    @Test func signedOutDoesNothing() async throws {
        let rig = try make(); let engine = rig.engine, library = rig.library, transport = rig.transport
        library.createCollection(name: "Top Shelf")
        await engine.syncNow()
        #expect(transport.pushed.isEmpty)
    }

    @Test func editsGoUpAndComeBackClean() async throws {
        let rig = try make(); let engine = rig.engine, library = rig.library, transport = rig.transport, auth = rig.auth, context = rig.context
        _ = try await auth.signInWithApple(identityToken: Data(), fullName: nil)
        let shelf = library.createCollection(name: "Top Shelf")
        library.add(show: cornell, to: shelf)
        // the journal stays on the phone
        _ = library.addJournalEntry(show: cornell, body: "Never the same.", mood: "hot")
        await engine.syncNow()
        let batch = try #require(transport.pushed.first)
        #expect(batch.shelves.map(\.name) == ["Top Shelf"])
        #expect(batch.shelfItems.count == 1)
        #expect(batch.shelfItems[0].shelfId == shelf.id.uuidString.uppercased())
        #expect(batch.shelfItems[0].showDate == "1977-05-08")
        #expect(batch.journalEntries.isEmpty)
        #expect(batch.mixtapes.isEmpty)
        // nothing left to push
        let dirty = try context.fetch(FetchDescriptor<ShowCollection>(predicate: #Predicate { $0.needsPush == true }))
        #expect(dirty.isEmpty)
        await engine.syncNow()
        #expect(transport.pushed.count == 1)
        #expect(engine.status == .idle)
        #expect(engine.lastSyncedAt != nil)
    }

    @Test func deletesTravelAsTombstones() async throws {
        let rig = try make(); let engine = rig.engine, library = rig.library, transport = rig.transport, auth = rig.auth, context = rig.context
        _ = try await auth.signInWithApple(identityToken: Data(), fullName: nil)
        let shelf = library.createCollection(name: "Gone")
        library.add(show: cornell, to: shelf)
        await engine.syncNow()
        library.deleteCollection(shelf)
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).count == 2)
        await engine.syncNow()
        let batch = try #require(transport.pushed.last)
        #expect(batch.shelves.first?.deletedAt != nil)
        #expect(batch.shelfItems.first?.deletedAt != nil)
        #expect(try context.fetch(FetchDescriptor<SyncTombstone>()).isEmpty)
    }

    @Test func pullsInsertOverwriteAndDelete() async throws {
        let rig = try make(); let engine = rig.engine, library = rig.library, transport = rig.transport, auth = rig.auth, context = rig.context
        _ = try await auth.signInWithApple(identityToken: Data(), fullName: nil)
        let mine = library.createCollection(name: "Mine")
        await engine.syncNow()
        let remoteID = UUID()
        let now = Date.now
        let stamp = NetheadDates.string(now)
        transport.answerPulls(with: SyncPull(
            cursor: 20,
            shelves: [
                SyncShelf(id: remoteID.uuidString, name: "From the Web", blurb: "", iconName: "sparkles", isPrivate: false, createdAt: stamp, updatedAt: stamp, deletedAt: nil),
                // a stale rename of mine loses
                SyncShelf(id: mine.id.uuidString, name: "Stale", blurb: "", iconName: "sparkles", isPrivate: false, createdAt: stamp,
                          updatedAt: NetheadDates.string(now.addingTimeInterval(-3600)), deletedAt: nil),
            ],
            shelfItems: [SyncShelfItem(id: UUID().uuidString, shelfId: remoteID.uuidString, showIdentifier: cornell.identifier, showId: "1977-05-08",
                                       showDate: "1977-05-08", displayName: "5/8/77 Barton Hall", sortIndex: 0, addedAt: stamp, updatedAt: stamp, deletedAt: nil)],
            // mix tapes on the web are the web's business
            mixtapes: [SyncMixtape(id: UUID().uuidString, name: "Site Tape", blurb: "", iconName: "music.note.list", isPrivate: false, createdAt: stamp, updatedAt: stamp, deletedAt: nil)],
            journalEntries: []))
        await engine.syncNow()
        let shelves = library.collections
        #expect(shelves.map(\.name).sorted() == ["From the Web", "Mine"])
        let web = try #require(shelves.first { $0.name == "From the Web" })
        #expect(web.items?.count == 1)
        #expect(web.needsPush == false)
        #expect(library.playlists.isEmpty)
        // a fresh rename from the web wins, and a tombstone removes the row
        let later = NetheadDates.string(now.addingTimeInterval(60))
        transport.answerPulls(with: SyncPull(cursor: 30, shelves: [
            SyncShelf(id: mine.id.uuidString, name: "Renamed on the Web", blurb: "", iconName: "sparkles", isPrivate: false, createdAt: stamp, updatedAt: later, deletedAt: nil),
            SyncShelf(id: remoteID.uuidString, name: "", blurb: "", iconName: "sparkles", isPrivate: false, createdAt: stamp, updatedAt: later, deletedAt: later),
        ]))
        await engine.syncNow()
        #expect(library.collections.map(\.name) == ["Renamed on the Web"])
        #expect(try context.fetch(FetchDescriptor<CollectionItem>()).isEmpty)
        // pulled rows never bounce back up
        #expect(transport.pushed.allSatisfy { batch in !batch.shelves.contains { $0.name == "From the Web" } })
    }

    @Test func gettingOnTheBusUploadsTheWholeLibrary() async throws {
        let rig = try make(); let engine = rig.engine, library = rig.library, transport = rig.transport, auth = rig.auth
        let shelf = library.createCollection(name: "Before")
        library.add(show: cornell, to: shelf)
        await engine.syncNow()
        #expect(transport.pushed.isEmpty)
        _ = try await auth.signInWithApple(identityToken: Data(), fullName: nil)
        engine.handleAuthChange()
        await engine.syncNow()
        #expect(transport.pushed.contains { $0.shelves.map(\.name) == ["Before"] })
    }

    @Test func offlineKeepsChangesDirty() async throws {
        let rig = try make(); let engine = rig.engine, library = rig.library, transport = rig.transport, auth = rig.auth, context = rig.context
        _ = try await auth.signInWithApple(identityToken: Data(), fullName: nil)
        library.createCollection(name: "Later")
        transport.fail(with: .offline)
        await engine.syncNow()
        #expect(engine.status == .offline)
        #expect(try context.fetch(FetchDescriptor<ShowCollection>(predicate: #Predicate { $0.needsPush == true })).count == 1)
        transport.fail(with: nil)
        await engine.syncNow()
        #expect(engine.status == .idle)
        #expect(transport.pushed.count == 1)
    }

    @Test func backfillGivesDuplicateIdsTheirOwn() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        let shelf = ShowCollection(name: "x")
        context.insert(shelf)
        let shared = UUID()
        for n in 0..<3 {
            let item = CollectionItem(showIdentifier: "gd\(n)", showDate: nil, displayName: "\(n)", sortIndex: n)
            item.id = shared
            item.collection = shelf
            context.insert(item)
        }
        try context.save()
        SyncSchemaBackfill.run(context: context)
        let ids = Set(try context.fetch(FetchDescriptor<CollectionItem>()).map(\.id))
        #expect(ids.count == 3)
        #expect(ids.contains(shared))
    }

    @Test func mapperRoundTripsDates() {
        let d = Date(timeIntervalSince1970: 1_700_000_000.123)
        let s = NetheadDates.string(d)
        #expect(s.hasSuffix("Z"))
        #expect(abs((NetheadDates.date(s) ?? .distantPast).timeIntervalSince(d)) < 0.001)
        #expect(NetheadDates.date("2026-09-05T21:09:01.761Z") != nil)
        #expect(NetheadDates.date("2026-09-05T21:09:01Z") != nil)
        #expect(NetheadDates.day(Date(timeIntervalSince1970: 231897600)) == "1977-05-08")
    }
}
