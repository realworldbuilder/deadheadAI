import Foundation
import OSLog
import SwiftData

/// The wire, abstracted so tests can stand in for the notesfile.
nonisolated protocol SyncTransport: Sendable {
    func pull(since: Int) async throws -> SyncPull
    func push(_ batch: SyncBatch) async throws -> SyncPushResult
}

extension NetheadAPIClient: SyncTransport {}

/// No notesfile configured: every call says so.
nonisolated struct NoSyncTransport: SyncTransport {
    func pull(since: Int) async throws -> SyncPull { throw NetheadAPIError.notConfigured }
    func push(_ batch: SyncBatch) async throws -> SyncPushResult { throw NetheadAPIError.notConfigured }
}

/// Keeps the phone's shelves, mix tapes and journal in step with the
/// notesfile: push what changed here, pull what changed there, last writer
/// wins by `updatedAt`, deletes travel as tombstones. One cycle at a time.
@Observable
final class SyncEngine {
    enum Status: Equatable {
        case idle, syncing, offline
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastSyncedAt: Date?

    private let context: ModelContext
    private let library: LibraryStore
    private let transport: any SyncTransport
    private let auth: any AuthProvider
    private let defaults: UserDefaults
    private let log = Logger(subsystem: "ai.deadheads", category: "sync")
    private var inFlight: Task<Void, Never>?
    private var pendingAgain = false
    private var mutationTask: Task<Void, Never>?

    init(container: ModelContainer, library: LibraryStore, transport: any SyncTransport,
         auth: any AuthProvider, defaults: UserDefaults = .standard) {
        self.context = container.mainContext
        self.library = library
        self.transport = transport
        self.auth = auth
        self.defaults = defaults
    }

    var isSignedIn: Bool { auth.currentAccount != nil }

    // MARK: - Triggers

    /// Launch, foreground, pull-to-refresh, sign-in. Coalesces: a call during a cycle queues one more.
    func syncNow() async {
        guard isSignedIn else { return }
        if let inFlight {
            pendingAgain = true
            await inFlight.value
            return
        }
        let task = Task { await runCycle() }
        inFlight = task
        await task.value
        inFlight = nil
        if pendingAgain {
            pendingAgain = false
            await syncNow()
        }
    }

    /// Three seconds after the last edit, push.
    func scheduleAfterMutation() {
        guard isSignedIn else { return }
        mutationTask?.cancel()
        mutationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// The phone got on or off the bus.
    func handleAuthChange() {
        mutationTask?.cancel()
        if let account = auth.currentAccount {
            log.notice("On the bus as \(account.handle, privacy: .public); first sync")
            markEverythingDirty()
            defaults.removeObject(forKey: cursorKey(for: account.id))
            Task { await syncNow() }
        } else {
            status = .idle
        }
    }

    // MARK: - The cycle

    private func cursorKey(for accountID: String) -> String { "nethead.sync.cursor.\(accountID)" }

    private var cursor: Int {
        get { auth.currentAccount.map { defaults.integer(forKey: cursorKey(for: $0.id)) } ?? 0 }
        set { if let account = auth.currentAccount { defaults.set(newValue, forKey: cursorKey(for: account.id)) } }
    }

    private func runCycle() async {
        status = .syncing
        do {
            try await push()
            try await pull()
            library.dedupAfterSync()
            lastSyncedAt = .now
            status = .idle
        } catch NetheadAPIError.offline {
            status = .offline
        } catch NetheadAPIError.notOnTheBus {
            status = .idle
            await auth.refresh()
        } catch NetheadAPIError.notConfigured {
            status = .idle
        } catch {
            log.error("Sync failed: \(String(describing: error), privacy: .public)")
            status = .failed("The notesfile didn't answer. Your changes are kept here and go up next time.")
        }
    }

    /// Every row that changed here since the notesfile last saw it, plus the tombstones.
    private func push() async throws {
        let dirty = dirtySnapshots()
        var batch = SyncMapper.tombstones(dirty.tombstones)
        batch.shelves += dirty.shelves.map(SyncMapper.shelf)
        batch.shelfItems += dirty.shelfItems.map(SyncMapper.shelfItem)
        batch.mixtapes += dirty.mixtapes.map(SyncMapper.mixtape)
        batch.mixtapeItems += dirty.mixtapeItems.map(SyncMapper.mixtapeItem)
        batch.journalEntries += dirty.journal.map(SyncMapper.journal)
        guard !batch.isEmpty else { return }
        // Five hundred rows a push; the rest goes next cycle.
        if batch.count > 500 { pendingAgain = true }
        let result = try await transport.push(trim(batch, to: 500))
        clearDirty(dirty)
        cursor = max(cursor, result.cursor)
        log.notice("Pushed \(result.accepted) rows")
    }

    private func trim(_ batch: SyncBatch, to limit: Int) -> SyncBatch {
        var out = SyncBatch()
        var room = limit
        func take<T>(_ rows: [T]) -> [T] { let n = min(room, rows.count); room -= n; return Array(rows.prefix(n)) }
        out.shelves = take(batch.shelves)
        out.mixtapes = take(batch.mixtapes)
        out.shelfItems = take(batch.shelfItems)
        out.mixtapeItems = take(batch.mixtapeItems)
        out.journalEntries = take(batch.journalEntries)
        return out
    }

    private func pull() async throws {
        let pulled = try await transport.pull(since: cursor)
        apply(pulled)
        try? context.save()
        cursor = max(cursor, pulled.cursor)
    }

    // MARK: - Local rows in and out

    private struct DirtyRows {
        var shelves: [ShowCollectionSnapshot] = []
        var shelfItems: [CollectionItemSnapshot] = []
        var mixtapes: [PlaylistSnapshot] = []
        var mixtapeItems: [PlaylistItemSnapshot] = []
        var journal: [JournalSnapshot] = []
        var tombstones: [TombstoneSnapshot] = []
        var updatedAtByID: [UUID: Date] = [:]
    }

    private func dirtySnapshots() -> DirtyRows {
        var out = DirtyRows()
        for c in (try? context.fetch(FetchDescriptor<ShowCollection>(predicate: #Predicate { $0.needsPush == true }))) ?? [] {
            out.shelves.append(ShowCollectionSnapshot(id: c.id, name: c.name, blurb: c.blurb, iconName: c.iconName, createdAt: c.createdAt, updatedAt: c.updatedAt))
            out.updatedAtByID[c.id] = c.updatedAt
        }
        for i in (try? context.fetch(FetchDescriptor<CollectionItem>(predicate: #Predicate { $0.needsPush == true }))) ?? [] {
            guard let parent = i.collection else { continue }
            out.shelfItems.append(CollectionItemSnapshot(id: i.id, collectionID: parent.id, showIdentifier: i.showIdentifier, showDate: i.showDate, displayName: i.displayName, sortIndex: i.sortIndex, addedAt: i.addedAt, updatedAt: i.updatedAt))
            out.updatedAtByID[i.id] = i.updatedAt
        }
        for p in (try? context.fetch(FetchDescriptor<Playlist>(predicate: #Predicate { $0.needsPush == true }))) ?? [] {
            out.mixtapes.append(PlaylistSnapshot(id: p.id, name: p.name, blurb: p.blurb, iconName: p.iconName, createdAt: p.createdAt, updatedAt: p.updatedAt))
            out.updatedAtByID[p.id] = p.updatedAt
        }
        for i in (try? context.fetch(FetchDescriptor<PlaylistItem>(predicate: #Predicate { $0.needsPush == true }))) ?? [] {
            guard let parent = i.playlist else { continue }
            out.mixtapeItems.append(PlaylistItemSnapshot(id: i.id, playlistID: parent.id, showIdentifier: i.showIdentifier, fileName: i.fileName, trackTitle: i.trackTitle, songKey: i.songKey, showDateString: i.showDateString, showDisplayName: i.showDisplayName, durationSeconds: i.durationSeconds, sortIndex: i.sortIndex, addedAt: i.addedAt, updatedAt: i.updatedAt))
            out.updatedAtByID[i.id] = i.updatedAt
        }
        for e in (try? context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.needsPush == true }))) ?? [] {
            out.journal.append(JournalSnapshot(id: e.id, showIdentifier: e.showIdentifier, showDate: e.showDate, showDisplayName: e.showDisplayName, body: e.body, mood: e.mood, createdAt: e.createdAt, updatedAt: e.updatedAt))
            out.updatedAtByID[e.id] = e.updatedAt
        }
        for t in (try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? [] {
            out.tombstones.append(TombstoneSnapshot(id: t.id, kind: t.kind, parentID: t.parentID, deletedAt: t.deletedAt))
        }
        return out
    }

    /// A row edited again while the push was in flight stays dirty.
    private func clearDirty(_ dirty: DirtyRows) {
        let ids = dirty.updatedAtByID
        for c in (try? context.fetch(FetchDescriptor<ShowCollection>(predicate: #Predicate { $0.needsPush == true }))) ?? [] where ids[c.id] == c.updatedAt { c.needsPush = false }
        for i in (try? context.fetch(FetchDescriptor<CollectionItem>(predicate: #Predicate { $0.needsPush == true }))) ?? [] where ids[i.id] == i.updatedAt { i.needsPush = false }
        for p in (try? context.fetch(FetchDescriptor<Playlist>(predicate: #Predicate { $0.needsPush == true }))) ?? [] where ids[p.id] == p.updatedAt { p.needsPush = false }
        for i in (try? context.fetch(FetchDescriptor<PlaylistItem>(predicate: #Predicate { $0.needsPush == true }))) ?? [] where ids[i.id] == i.updatedAt { i.needsPush = false }
        for e in (try? context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.needsPush == true }))) ?? [] where ids[e.id] == e.updatedAt { e.needsPush = false }
        let acked = Set(dirty.tombstones.map(\.id))
        for t in (try? context.fetch(FetchDescriptor<SyncTombstone>())) ?? [] where acked.contains(t.id) { context.delete(t) }
        try? context.save()
    }

    private func markEverythingDirty() {
        for c in (try? context.fetch(FetchDescriptor<ShowCollection>())) ?? [] { c.needsPush = true }
        for i in (try? context.fetch(FetchDescriptor<CollectionItem>())) ?? [] { i.needsPush = true }
        for p in (try? context.fetch(FetchDescriptor<Playlist>())) ?? [] { p.needsPush = true }
        for i in (try? context.fetch(FetchDescriptor<PlaylistItem>())) ?? [] { i.needsPush = true }
        for e in (try? context.fetch(FetchDescriptor<JournalEntry>())) ?? [] { e.needsPush = true }
        try? context.save()
    }

    private func fetchOne<T: PersistentModel>(_ type: T.Type, _ predicate: Predicate<T>) -> T? {
        var d = FetchDescriptor<T>(predicate: predicate)
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    private func dropTombstone(_ id: UUID) {
        if let t = fetchOne(SyncTombstone.self, #Predicate { $0.id == id }) { context.delete(t) }
    }

    /// Rows from the notesfile, oldest first; parents before children.
    private func apply(_ pulled: SyncPull) {
        for r in pulled.shelves {
            guard let id = SyncMapper.uuid(r.id) else { continue }
            let remoteUpdated = NetheadDates.date(r.updatedAt) ?? .distantPast
            let local = fetchOne(ShowCollection.self, #Predicate { $0.id == id })
            if let deletedAt = NetheadDates.date(r.deletedAt) {
                if let local, local.updatedAt <= deletedAt { context.delete(local) }
                dropTombstone(id)
                continue
            }
            if let local {
                guard remoteUpdated > local.updatedAt else { continue }
                local.name = r.name; local.blurb = r.blurb; local.iconName = r.iconName
                local.updatedAt = remoteUpdated; local.needsPush = false
            } else {
                let c = ShowCollection(name: r.name, blurb: r.blurb, iconName: r.iconName)
                c.id = id; c.createdAt = NetheadDates.date(r.createdAt) ?? .now; c.updatedAt = remoteUpdated; c.needsPush = false
                context.insert(c)
            }
        }
        for r in pulled.shelfItems {
            guard let id = SyncMapper.uuid(r.id), let parentID = SyncMapper.uuid(r.shelfId) else { continue }
            let remoteUpdated = NetheadDates.date(r.updatedAt) ?? .distantPast
            let local = fetchOne(CollectionItem.self, #Predicate { $0.id == id })
            if let deletedAt = NetheadDates.date(r.deletedAt) {
                if let local, local.updatedAt <= deletedAt { context.delete(local) }
                dropTombstone(id)
                continue
            }
            guard let parent = fetchOne(ShowCollection.self, #Predicate { $0.id == parentID }) else { continue }
            if let local {
                guard remoteUpdated > local.updatedAt else { continue }
                local.showIdentifier = r.showIdentifier; local.showDate = NetheadDates.date(r.showDate); local.displayName = r.displayName
                local.sortIndex = r.sortIndex; local.collection = parent; local.updatedAt = remoteUpdated; local.needsPush = false
            } else {
                let i = CollectionItem(showIdentifier: r.showIdentifier, showDate: NetheadDates.date(r.showDate), displayName: r.displayName, sortIndex: r.sortIndex)
                i.id = id; i.addedAt = NetheadDates.date(r.addedAt) ?? .now; i.updatedAt = remoteUpdated; i.needsPush = false; i.collection = parent
                context.insert(i)
            }
        }
        for r in pulled.mixtapes {
            guard let id = SyncMapper.uuid(r.id) else { continue }
            let remoteUpdated = NetheadDates.date(r.updatedAt) ?? .distantPast
            let local = fetchOne(Playlist.self, #Predicate { $0.id == id })
            if let deletedAt = NetheadDates.date(r.deletedAt) {
                if let local, local.updatedAt <= deletedAt { context.delete(local) }
                dropTombstone(id)
                continue
            }
            if let local {
                guard remoteUpdated > local.updatedAt else { continue }
                local.name = r.name; local.blurb = r.blurb; local.iconName = r.iconName
                local.updatedAt = remoteUpdated; local.needsPush = false
            } else {
                let p = Playlist(name: r.name, blurb: r.blurb, iconName: r.iconName)
                p.id = id; p.createdAt = NetheadDates.date(r.createdAt) ?? .now; p.updatedAt = remoteUpdated; p.needsPush = false
                context.insert(p)
            }
        }
        for r in pulled.mixtapeItems {
            guard let id = SyncMapper.uuid(r.id), let parentID = SyncMapper.uuid(r.mixtapeId) else { continue }
            let remoteUpdated = NetheadDates.date(r.updatedAt) ?? .distantPast
            let local = fetchOne(PlaylistItem.self, #Predicate { $0.id == id })
            if let deletedAt = NetheadDates.date(r.deletedAt) {
                if let local, local.updatedAt <= deletedAt { context.delete(local) }
                dropTombstone(id)
                continue
            }
            guard let parent = fetchOne(Playlist.self, #Predicate { $0.id == parentID }) else { continue }
            if let local {
                guard remoteUpdated > local.updatedAt else { continue }
                local.trackTitle = r.trackTitle; local.songKey = r.songKey; local.showDateString = r.showDateString
                local.showDisplayName = r.showDisplayName; local.durationSeconds = r.durationSeconds; local.sortIndex = r.sortIndex
                local.playlist = parent; local.updatedAt = remoteUpdated; local.needsPush = false
            } else {
                let i = PlaylistItem(showIdentifier: r.showIdentifier, fileName: r.fileName, trackTitle: r.trackTitle, songKey: r.songKey,
                                     showDateString: r.showDateString, showDisplayName: r.showDisplayName, durationSeconds: r.durationSeconds, sortIndex: r.sortIndex)
                i.id = id; i.addedAt = NetheadDates.date(r.addedAt) ?? .now; i.updatedAt = remoteUpdated; i.needsPush = false; i.playlist = parent
                context.insert(i)
            }
        }
        for r in pulled.journalEntries {
            guard let id = SyncMapper.uuid(r.id) else { continue }
            let remoteUpdated = NetheadDates.date(r.updatedAt) ?? .distantPast
            let local = fetchOne(JournalEntry.self, #Predicate { $0.id == id })
            if let deletedAt = NetheadDates.date(r.deletedAt) {
                if let local, local.updatedAt <= deletedAt { context.delete(local) }
                dropTombstone(id)
                continue
            }
            if let local {
                guard remoteUpdated > local.updatedAt else { continue }
                local.body = r.body; local.mood = r.mood; local.showDisplayName = r.showDisplayName
                local.updatedAt = remoteUpdated; local.needsPush = false
            } else {
                let e = JournalEntry(showIdentifier: r.showIdentifier, showDate: NetheadDates.date(r.showDate), showDisplayName: r.showDisplayName, body: r.body, mood: r.mood)
                e.id = id; e.createdAt = NetheadDates.date(r.createdAt) ?? .now; e.updatedAt = remoteUpdated; e.needsPush = false
                context.insert(e)
            }
        }
    }
}

/// Existing rows get one shared default UUID when a store migrates to the
/// new `id` columns; give every duplicate its own before the first sync.
enum SyncSchemaBackfill {
    static let flagKey = "syncSchemaBackfillV1Done"

    static func runIfNeeded(container: ModelContainer, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: flagKey) else { return }
        run(context: container.mainContext)
        defaults.set(true, forKey: flagKey)
    }

    static func run(context: ModelContext) {
        var seen: Set<UUID> = []
        for item in (try? context.fetch(FetchDescriptor<CollectionItem>())) ?? [] {
            if !seen.insert(item.id).inserted { item.id = UUID() }
        }
        seen = []
        for item in (try? context.fetch(FetchDescriptor<PlaylistItem>())) ?? [] {
            if !seen.insert(item.id).inserted { item.id = UUID() }
        }
        try? context.save()
    }
}
