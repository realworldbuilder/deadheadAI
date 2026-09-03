import Foundation
import SQLite3

// Thin reader over the bundled read-only catalog.sqlite. An actor owns the
// sqlite handle so all access is serialized off the main thread; the
// MainActor facade (CatalogStore) awaits into it, mirroring how providers
// await into the networking layer.

private nonisolated let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Owns the sqlite handle so it closes when the actor goes away — an
/// actor's own deinit can't touch non-Sendable stored state.
private nonisolated final class SQLiteHandle: @unchecked Sendable {
    let ptr: OpaquePointer
    init(_ ptr: OpaquePointer) { self.ptr = ptr }
    deinit { sqlite3_close_v2(ptr) }
}

nonisolated actor CatalogDB {
    private let handle: SQLiteHandle
    private var db: OpaquePointer { handle.ptr }

    /// Opens read-only. Returns nil when the file is missing, unreadable,
    /// or a different schema version — callers degrade to network-only.
    init?(fileURL: URL, expectedSchemaVersion: Int = 2) {
        var handle: OpaquePointer?
        let uri = "file:\(fileURL.path(percentEncoded: false))?immutable=1"
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close_v2(handle) }
            return nil
        }
        // Validate the schema contract before anything queries.
        var stmt: OpaquePointer?
        var version: Int?
        if sqlite3_prepare_v2(handle, "SELECT value FROM catalog_meta WHERE key='schema_version'", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW,
           let text = sqlite3_column_text(stmt, 0) {
            version = Int(String(cString: text))
        }
        sqlite3_finalize(stmt)
        guard version == expectedSchemaVersion else {
            sqlite3_close_v2(handle)
            return nil
        }
        self.handle = SQLiteHandle(handle)
    }

    // MARK: - Meta

    func meta() -> [String: String] {
        var out: [String: String] = [:]
        query("SELECT key, value FROM catalog_meta") { stmt in
            out[Self.text(stmt, 0) ?? ""] = Self.text(stmt, 1) ?? ""
        }
        return out
    }

    // MARK: - Shows

    private static let showColumns = """
        show_id, date, year, month, day, era_id, venue, city, state, setlist_status,
        recording_count, best_identifier, best_source_type, avg_rating, total_reviews, total_downloads,
        cover_image_url
        """

    func show(id: String) -> CatalogShow? {
        var result: CatalogShow?
        query("SELECT \(Self.showColumns) FROM shows WHERE show_id = ?", bind: [.text(id)]) { stmt in
            result = Self.decodeShow(stmt)
        }
        return result
    }

    func shows(onDate date: String) -> [CatalogShow] {
        collectShows("SELECT \(Self.showColumns) FROM shows WHERE date = ? ORDER BY show_id", bind: [.text(date)])
    }

    /// Scans from the nights closest to `date` — usually the same run or
    /// tour — nearest first, for shows that have no usable scan of their
    /// own. The night itself is skipped: its scan is what just failed.
    func nearestCoverImageURLs(toDate date: String, limit: Int) -> [String] {
        var found: [String] = []
        query("""
            SELECT cover_image_url FROM shows
            WHERE cover_image_url IS NOT NULL AND date != ?
            ORDER BY abs(julianday(date) - julianday(?)) LIMIT ?
            """, bind: [.text(date), .text(date), .int(limit)]) { stmt in
            if let url = Self.text(stmt, 0) { found.append(url) }
        }
        return found
    }

    /// Every memorabilia scan for a night, cover first.
    func images(onDate date: String) -> [CatalogImage] {
        var found: [CatalogImage] = []
        query("""
            SELECT date, position, kind, url, width, height FROM show_images
            WHERE date = ? ORDER BY position
            """, bind: [.text(date)]) { stmt in
            guard let date = Self.text(stmt, 0), let url = Self.text(stmt, 3) else { return }
            found.append(CatalogImage(
                date: date,
                position: Int(sqlite3_column_int(stmt, 1)),
                kind: CatalogImage.Kind(rawValue: Self.text(stmt, 2) ?? "") ?? .other,
                url: url,
                width: Self.integer(stmt, 4),
                height: Self.integer(stmt, 5)))
        }
        return found
    }

    func shows(inYear year: Int) -> [CatalogShow] {
        collectShows("SELECT \(Self.showColumns) FROM shows WHERE year = ? ORDER BY date", bind: [.int(year)])
    }

    func shows(month: Int, day: Int) -> [CatalogShow] {
        collectShows("SELECT \(Self.showColumns) FROM shows WHERE month = ? AND day = ? ORDER BY year",
                     bind: [.int(month), .int(day)])
    }

    func topRated(yearRange: ClosedRange<Int>?, limit: Int) -> [CatalogShow] {
        var sql = """
            SELECT \(Self.showColumns) FROM shows
            WHERE avg_rating >= 4.3 AND total_reviews >= 5
            """
        var binds: [Binding] = []
        if let yearRange {
            sql += " AND year BETWEEN ? AND ?"
            binds += [.int(yearRange.lowerBound), .int(yearRange.upperBound)]
        }
        sql += " ORDER BY avg_rating DESC, total_reviews DESC LIMIT ?"
        binds.append(.int(limit))
        return collectShows(sql, bind: binds)
    }

    func searchText(_ raw: String, limit: Int) -> [CatalogShow] {
        guard let match = Self.ftsQuery(from: raw) else { return [] }
        return collectShows("""
            SELECT \(Self.showColumns.replacingOccurrences(of: "show_id", with: "s.show_id"))
            FROM show_fts JOIN shows s ON s.rowid = show_fts.rowid
            WHERE show_fts MATCH ?
            ORDER BY rank LIMIT ?
            """, bind: [.text(match), .int(limit)])
    }

    func yearCounts() -> [(year: Int, count: Int)] {
        var out: [(Int, Int)] = []
        query("SELECT year, COUNT(*) FROM shows GROUP BY year ORDER BY year") { stmt in
            out.append((Int(sqlite3_column_int(stmt, 0)), Int(sqlite3_column_int(stmt, 1))))
        }
        return out
    }

    func venues(matching prefix: String?, limit: Int) -> [VenueSummary] {
        var sql = """
            SELECT venue, city, COUNT(*) AS n FROM shows
            WHERE venue IS NOT NULL AND venue != ''
            """
        var binds: [Binding] = []
        if let prefix, !prefix.isEmpty {
            sql += " AND venue LIKE ? ESCAPE '\\'"
            let escaped = prefix
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            binds.append(.text("%\(escaped)%"))
        }
        sql += " GROUP BY venue, city ORDER BY n DESC LIMIT ?"
        binds.append(.int(limit))
        var out: [VenueSummary] = []
        query(sql, bind: binds) { stmt in
            out.append(VenueSummary(venue: Self.text(stmt, 0) ?? "",
                                    city: Self.text(stmt, 1),
                                    showCount: Int(sqlite3_column_int(stmt, 2))))
        }
        return out
    }

    func shows(atVenue venue: String) -> [CatalogShow] {
        collectShows("SELECT \(Self.showColumns) FROM shows WHERE venue = ? ORDER BY date", bind: [.text(venue)])
    }

    // MARK: - Recordings

    func recordings(forShow showID: String) -> [CatalogRecording] {
        var out: [CatalogRecording] = []
        query("""
            SELECT identifier, show_id, title, source_type, source_text, lineage, taper,
                   avg_rating, num_reviews, downloads, quality_score
            FROM recordings WHERE show_id = ? ORDER BY quality_score DESC
            """, bind: [.text(showID)]) { stmt in
            out.append(CatalogRecording(
                identifier: Self.text(stmt, 0) ?? "",
                showID: Self.text(stmt, 1) ?? "",
                title: Self.text(stmt, 2),
                sourceType: SourceType(rawValue: Self.text(stmt, 3) ?? "") ?? .unknown,
                sourceText: Self.text(stmt, 4),
                lineage: Self.text(stmt, 5),
                taper: Self.text(stmt, 6),
                avgRating: Self.real(stmt, 7),
                numReviews: Int(sqlite3_column_int(stmt, 8)),
                downloads: Int(sqlite3_column_int(stmt, 9)),
                qualityScore: sqlite3_column_double(stmt, 10)))
        }
        return out
    }

    func recording(identifier: String) -> CatalogRecording? {
        var out: CatalogRecording?
        query("""
            SELECT identifier, show_id, title, source_type, source_text, lineage, taper,
                   avg_rating, num_reviews, downloads, quality_score
            FROM recordings WHERE identifier = ?
            """, bind: [.text(identifier)]) { stmt in
            out = CatalogRecording(
                identifier: Self.text(stmt, 0) ?? "",
                showID: Self.text(stmt, 1) ?? "",
                title: Self.text(stmt, 2),
                sourceType: SourceType(rawValue: Self.text(stmt, 3) ?? "") ?? .unknown,
                sourceText: Self.text(stmt, 4),
                lineage: Self.text(stmt, 5),
                taper: Self.text(stmt, 6),
                avgRating: Self.real(stmt, 7),
                numReviews: Int(sqlite3_column_int(stmt, 8)),
                downloads: Int(sqlite3_column_int(stmt, 9)),
                qualityScore: sqlite3_column_double(stmt, 10))
        }
        return out
    }

    // MARK: - Setlists & songs

    func setlist(forShow showID: String) -> Setlist? {
        guard let show = show(id: showID), show.setlistStatus != .none else { return nil }
        var entries: [SetlistEntry] = []
        query("""
            SELECT position, set_label, song_key, song_title, segues_into_next
            FROM setlist_entries WHERE show_id = ? ORDER BY position
            """, bind: [.text(showID)]) { stmt in
            entries.append(SetlistEntry(
                position: Int(sqlite3_column_int(stmt, 0)),
                setLabel: Self.text(stmt, 1) ?? "Set 1",
                songKey: Self.text(stmt, 2) ?? "",
                songTitle: Self.text(stmt, 3) ?? "",
                seguesIntoNext: sqlite3_column_int(stmt, 4) != 0))
        }
        guard !entries.isEmpty else { return nil }
        return Setlist(showID: showID, status: show.setlistStatus, entries: entries)
    }

    /// Taper-spelling variants → canonical song key ("one more saturday
    /// nite" → "one more saturday night"), from the pipeline's alias table.
    func songAliases() -> [String: String] {
        var out: [String: String] = [:]
        query("SELECT variant_key, canonical_key FROM song_aliases") { stmt in
            if let variant = Self.text(stmt, 0), let canonical = Self.text(stmt, 1) {
                out[variant] = canonical
            }
        }
        return out
    }

    func song(forKey key: String) -> SongStats? {
        var out: SongStats?
        query("SELECT song_key, title, times_played, first_played, last_played FROM songs WHERE song_key = ?",
              bind: [.text(key)]) { stmt in
            out = SongStats(songKey: Self.text(stmt, 0) ?? "",
                            title: Self.text(stmt, 1) ?? "",
                            timesPlayed: Int(sqlite3_column_int(stmt, 2)),
                            firstPlayed: Self.text(stmt, 3),
                            lastPlayed: Self.text(stmt, 4))
        }
        return out
    }

    func performances(ofSong key: String) -> [CatalogShow] {
        collectShows("""
            SELECT \(Self.showColumns.replacingOccurrences(of: "show_id", with: "s.show_id"))
            FROM setlist_entries e JOIN shows s ON s.show_id = e.show_id
            WHERE e.song_key = ?
            GROUP BY s.show_id ORDER BY s.date
            """, bind: [.text(key)])
    }

    func digest(forShow showID: String) -> ShowDigest? {
        var out: ShowDigest?
        query("""
            SELECT show_id, consensus_summary, standout_songs_json, sentiment, derived_rating, rating_rationale
            FROM ai_digest WHERE show_id = ?
            """, bind: [.text(showID)]) { stmt in
            let songsJSON = Self.text(stmt, 2) ?? "[]"
            let songs = (try? JSONDecoder().decode([String].self, from: Data(songsJSON.utf8))) ?? []
            out = ShowDigest(showID: Self.text(stmt, 0) ?? "",
                             consensusSummary: Self.text(stmt, 1) ?? "",
                             standoutSongs: songs,
                             sentiment: Self.text(stmt, 3) ?? "mixed",
                             derivedRating: sqlite3_column_double(stmt, 4),
                             ratingRationale: Self.text(stmt, 5) ?? "")
        }
        return out
    }

    // MARK: - Plumbing

    enum Binding {
        case text(String)
        case int(Int)
    }

    private func query(_ sql: String, bind: [Binding] = [], row: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            assertionFailure("catalog SQL failed to prepare: \(sql)")
            return
        }
        defer { sqlite3_finalize(stmt) }
        for (i, binding) in bind.enumerated() {
            switch binding {
            case .text(let value): sqlite3_bind_text(stmt, Int32(i + 1), value, -1, SQLITE_TRANSIENT)
            case .int(let value): sqlite3_bind_int64(stmt, Int32(i + 1), Int64(value))
            }
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            row(stmt)
        }
    }

    private func collectShows(_ sql: String, bind: [Binding] = []) -> [CatalogShow] {
        var out: [CatalogShow] = []
        query(sql, bind: bind) { stmt in
            if let show = Self.decodeShow(stmt) { out.append(show) }
        }
        return out
    }

    private static func decodeShow(_ stmt: OpaquePointer) -> CatalogShow? {
        guard let showID = text(stmt, 0), let date = text(stmt, 1) else { return nil }
        return CatalogShow(
            showID: showID,
            date: date,
            year: Int(sqlite3_column_int(stmt, 2)),
            month: Int(sqlite3_column_int(stmt, 3)),
            day: Int(sqlite3_column_int(stmt, 4)),
            eraID: text(stmt, 5),
            venue: text(stmt, 6),
            city: text(stmt, 7),
            state: text(stmt, 8),
            setlistStatus: CatalogShow.SetlistStatus(rawValue: text(stmt, 9) ?? "none") ?? .none,
            recordingCount: Int(sqlite3_column_int(stmt, 10)),
            bestIdentifier: text(stmt, 11),
            bestSourceType: SourceType(rawValue: text(stmt, 12) ?? "") ?? .unknown,
            avgRating: real(stmt, 13),
            totalReviews: Int(sqlite3_column_int(stmt, 14)),
            totalDownloads: Int(sqlite3_column_int(stmt, 15)),
            coverImageURL: text(stmt, 16))
    }

    private static func text(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    private static func real(_ stmt: OpaquePointer, _ index: Int32) -> Double? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, index)
    }

    private static func integer(_ stmt: OpaquePointer, _ index: Int32) -> Int? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, index))
    }

    /// User text -> FTS5 MATCH query: each token quoted (so `5-8-77` stays
    /// one token and syntax chars can't inject) with prefix matching.
    static func ftsQuery(from raw: String) -> String? {
        let tokens = raw
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}
