import Foundation
import OSLog
import SwiftData

/// One-time copy of user shelves & journal out of the legacy single store into
/// the cloud-eligible store. Runs before the app's container opens anything.
///
/// Why a file backup first: the moment the main container opens `default.store`
/// without the three moved models, lightweight migration drops their tables.
/// Copying from a backup that the app never opens again means a failed attempt
/// always has original data to retry against next launch. The backup is never
/// deleted; the completion flag is set only after a successful save.
enum CloudStoreMigrator {
    static let flagKey = "cloudStoreMigrationV1Done"
    private static let log = Logger(subsystem: "ai.deadheads", category: "migration")

    static func migrateIfNeeded() {
        migrateIfNeeded(legacyURL: ModelContainerFactory.localStoreURL,
                        cloudURL: ModelContainerFactory.cloudStoreURL,
                        defaults: .standard)
    }

    static func migrateIfNeeded(legacyURL: URL, cloudURL: URL, defaults: UserDefaults) {
        guard !defaults.bool(forKey: flagKey) else { return }
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            // Fresh install — nothing to move.
            defaults.set(true, forKey: flagKey)
            return
        }
        do {
            let backupURL = try backUpIfNeeded(legacyURL: legacyURL)
            try migrate(from: backupURL, to: cloudURL)
            defaults.set(true, forKey: flagKey)
            log.notice("Cloud store migration complete")
        } catch {
            log.fault("Cloud store migration failed, will retry next launch: \(String(describing: error), privacy: .public)")
        }
    }

    /// Copies the legacy store files (main + -wal/-shm sidecars) once. The
    /// backup is the migration source on every attempt, so retries are immune
    /// to the main container having already reshaped `default.store`.
    private static func backUpIfNeeded(legacyURL: URL) throws -> URL {
        let fm = FileManager.default
        let backupURL = legacyURL.deletingLastPathComponent()
            .appending(path: "pre-cloud-backup.store")
        if !fm.fileExists(atPath: backupURL.path) {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(filePath: legacyURL.path + suffix)
                let target = URL(filePath: backupURL.path + suffix)
                if fm.fileExists(atPath: source.path) {
                    try fm.copyItem(at: source, to: target)
                }
            }
        }
        return backupURL
    }

    static func migrate(from sourceURL: URL, to targetURL: URL) throws {
        // The source opens with the full legacy schema (it holds every model);
        // lightweight migration applies the CloudKit loosening on the fly.
        let sourceSchema = Schema(ModelContainerFactory.allModels)
        let sourceConfig = ModelConfiguration(schema: sourceSchema, url: sourceURL, cloudKitDatabase: .none)
        let sourceContainer = try ModelContainer(for: sourceSchema, configurations: [sourceConfig])

        let targetSchema = Schema(ModelContainerFactory.cloudModels)
        let targetConfig = ModelConfiguration(schema: targetSchema, url: targetURL, cloudKitDatabase: .none)
        let targetContainer = try ModelContainer(for: targetSchema, configurations: [targetConfig])

        let source = sourceContainer.mainContext
        let target = targetContainer.mainContext

        // Copy only rows the target doesn't already have, so a re-run after a
        // partial save can't duplicate anything.
        let existingCollections = Set(try target.fetch(FetchDescriptor<ShowCollection>()).map(\.id))
        for collection in try source.fetch(FetchDescriptor<ShowCollection>())
        where !existingCollections.contains(collection.id) {
            let copy = ShowCollection(name: collection.name,
                                      blurb: collection.blurb,
                                      iconName: collection.iconName)
            copy.id = collection.id
            copy.createdAt = collection.createdAt
            target.insert(copy)
            for item in collection.items ?? [] {
                let itemCopy = CollectionItem(showIdentifier: item.showIdentifier,
                                              showDate: item.showDate,
                                              displayName: item.displayName,
                                              sortIndex: item.sortIndex)
                itemCopy.addedAt = item.addedAt
                itemCopy.collection = copy
                target.insert(itemCopy)
            }
        }

        let existingEntries = Set(try target.fetch(FetchDescriptor<JournalEntry>()).map(\.id))
        for entry in try source.fetch(FetchDescriptor<JournalEntry>())
        where !existingEntries.contains(entry.id) {
            let copy = JournalEntry(showIdentifier: entry.showIdentifier,
                                    showDate: entry.showDate,
                                    showDisplayName: entry.showDisplayName,
                                    body: entry.body,
                                    mood: entry.mood)
            copy.id = entry.id
            copy.createdAt = entry.createdAt
            copy.updatedAt = entry.updatedAt
            target.insert(copy)
        }

        try target.save()
    }
}
