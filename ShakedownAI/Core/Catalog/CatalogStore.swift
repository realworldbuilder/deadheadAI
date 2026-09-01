import Foundation

// MainActor seam over the bundled catalog. UI, providers, and the AI layer
// talk to `ShowCatalog`; `CatalogStore` awaits into the CatalogDB actor.
// When the catalog resource is missing or mismatched, `isAvailable` is
// false and every query returns empty — callers fall back to the network.

protocol ShowCatalog: AnyObject {
    var isAvailable: Bool { get }
    func meta() async -> [String: String]
    func show(withID id: String) async -> CatalogShow?
    func shows(onDate date: String) async -> [CatalogShow]
    func shows(inYear year: Int) async -> [CatalogShow]
    func shows(onMonthDay monthDay: String) async -> [CatalogShow]
    func topRated(yearRange: ClosedRange<Int>?, limit: Int) async -> [CatalogShow]
    func recordings(forShow showID: String) async -> [CatalogRecording]
    func recording(identifier: String) async -> CatalogRecording?
    func setlist(forShow showID: String) async -> Setlist?
    func digest(forShow showID: String) async -> ShowDigest?
    func searchText(_ query: String, limit: Int) async -> [CatalogShow]
    func song(forKey key: String) async -> SongStats?
    func songAliases() async -> [String: String]
    func performances(ofSong key: String) async -> [CatalogShow]
    func venues(matching prefix: String?, limit: Int) async -> [VenueSummary]
    func shows(atVenue venue: String) async -> [CatalogShow]
    func yearCounts() async -> [(year: Int, count: Int)]
}

extension ShowCatalog {
    /// Setlist for a plain date, resolving early/late double-show nights
    /// to whichever show actually has entries (early first).
    func setlist(forDate date: String) async -> Setlist? {
        if let direct = await setlist(forShow: date) { return direct }
        for suffix in ["-early", "-late"] {
            if let found = await setlist(forShow: date + suffix) { return found }
        }
        return nil
    }

    /// Show row for a plain date (first of an early/late pair).
    func show(onDate date: String) async -> CatalogShow? {
        await shows(onDate: date).first
    }
}

final class CatalogStore: ShowCatalog {
    private let db: CatalogDB?

    let isAvailable: Bool

    convenience init(bundle: Bundle = .main) {
        self.init(fileURL: bundle.url(forResource: "catalog", withExtension: "sqlite"))
    }

    init(fileURL: URL?) {
        if let fileURL, let db = CatalogDB(fileURL: fileURL) {
            self.db = db
            isAvailable = true
        } else {
            db = nil
            isAvailable = false
        }
    }

    func meta() async -> [String: String] {
        await db?.meta() ?? [:]
    }

    func show(withID id: String) async -> CatalogShow? {
        await db?.show(id: id)
    }

    func shows(onDate date: String) async -> [CatalogShow] {
        await db?.shows(onDate: date) ?? []
    }

    func shows(inYear year: Int) async -> [CatalogShow] {
        await db?.shows(inYear: year) ?? []
    }

    func shows(onMonthDay monthDay: String) async -> [CatalogShow] {
        let parts = monthDay.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) else { return [] }
        return await db?.shows(month: month, day: day) ?? []
    }

    func topRated(yearRange: ClosedRange<Int>?, limit: Int) async -> [CatalogShow] {
        await db?.topRated(yearRange: yearRange, limit: limit) ?? []
    }

    func recordings(forShow showID: String) async -> [CatalogRecording] {
        await db?.recordings(forShow: showID) ?? []
    }

    func recording(identifier: String) async -> CatalogRecording? {
        await db?.recording(identifier: identifier)
    }

    func setlist(forShow showID: String) async -> Setlist? {
        await db?.setlist(forShow: showID)
    }

    func digest(forShow showID: String) async -> ShowDigest? {
        await db?.digest(forShow: showID)
    }

    func searchText(_ query: String, limit: Int) async -> [CatalogShow] {
        await db?.searchText(query, limit: limit) ?? []
    }

    func song(forKey key: String) async -> SongStats? {
        await db?.song(forKey: key)
    }

    private var cachedAliases: [String: String]?

    func songAliases() async -> [String: String] {
        if let cachedAliases { return cachedAliases }
        let aliases = await db?.songAliases() ?? [:]
        cachedAliases = aliases
        return aliases
    }

    func performances(ofSong key: String) async -> [CatalogShow] {
        await db?.performances(ofSong: key) ?? []
    }

    func venues(matching prefix: String?, limit: Int) async -> [VenueSummary] {
        await db?.venues(matching: prefix, limit: limit) ?? []
    }

    func shows(atVenue venue: String) async -> [CatalogShow] {
        await db?.shows(atVenue: venue) ?? []
    }

    func yearCounts() async -> [(year: Int, count: Int)] {
        await db?.yearCounts() ?? []
    }
}
