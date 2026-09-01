import Foundation

// Domain types for the bundled read-only show catalog
// (Resources/catalog/catalog.sqlite, built by tools/catalog-pipeline).
// Like all domain models these are nonisolated Sendable values.

/// Recording provenance, detected by the pipeline from identifier
/// patterns and lineage analysis. Order is the quality ranking.
nonisolated enum SourceType: String, Codable, Sendable, CaseIterable {
    case soundboard = "SBD"
    case matrix = "MATRIX"
    case fm = "FM"
    case audience = "AUD"
    case unknown = "UNKNOWN"

    var displayName: String {
        switch self {
        case .soundboard: "Soundboard"
        case .matrix: "Matrix"
        case .fm: "FM Broadcast"
        case .audience: "Audience"
        case .unknown: "Unknown source"
        }
    }

    var badge: String {
        switch self {
        case .soundboard: "SBD"
        case .matrix: "MTX"
        case .fm: "FM"
        case .audience: "AUD"
        case .unknown: "?"
        }
    }

    var systemImage: String {
        switch self {
        case .soundboard: "slider.horizontal.3"
        case .matrix: "waveform.path"
        case .fm: "radio"
        case .audience: "recordingtape"
        case .unknown: "questionmark.circle"
        }
    }
}

/// One night (or one early/late show) in the catalog.
nonisolated struct CatalogShow: Sendable, Hashable, Identifiable {
    /// "1977-05-08", with "-early"/"-late" suffix for double-show dates.
    var showID: String
    /// Plain "yyyy-MM-dd".
    var date: String
    var year: Int
    var month: Int
    var day: Int
    var eraID: String?
    var venue: String?
    var city: String?
    var state: String?
    var setlistStatus: SetlistStatus
    var recordingCount: Int
    var bestIdentifier: String?
    var bestSourceType: SourceType
    var avgRating: Double?
    var totalReviews: Int
    var totalDownloads: Int
    /// Ticket stub / poster scan from jerrygarcia.com, hotlinked.
    var coverImageURL: String?

    var id: String { showID }

    nonisolated enum SetlistStatus: String, Sendable {
        case full, partial, none
    }

    var location: String? {
        let parts = [city, state].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The playable `Show` for this night's best tape, in the shape the
    /// rest of the app already speaks.
    var asShow: Show? {
        guard let bestIdentifier else { return nil }
        return Show(
            identifier: bestIdentifier,
            title: "Grateful Dead Live at \(venue ?? "Unknown venue") on \(date)",
            date: Self.isoDay.date(from: date),
            dateString: date,
            venue: venue,
            location: location,
            year: year,
            avgRating: avgRating,
            numReviews: totalReviews,
            downloads: totalDownloads,
            source: nil)
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

/// One archive.org tape of a show, with pipeline-computed ranking.
nonisolated struct CatalogRecording: Sendable, Hashable, Identifiable {
    var identifier: String
    var showID: String
    var title: String?
    var sourceType: SourceType
    var sourceText: String?
    var lineage: String?
    var taper: String?
    var avgRating: Double?
    var numReviews: Int
    var downloads: Int
    var qualityScore: Double

    var id: String { identifier }

    var asShow: Show {
        Show(
            identifier: identifier,
            title: title ?? identifier,
            date: nil,
            dateString: String(showID.prefix(10)),
            venue: nil,
            location: nil,
            year: Int(showID.prefix(4)),
            avgRating: avgRating,
            numReviews: numReviews,
            downloads: downloads,
            source: sourceText)
    }
}

/// One song slot in a show's setlist.
nonisolated struct SetlistEntry: Sendable, Hashable {
    var position: Int
    var setLabel: String
    /// Pre-normalized via the Track.normalizeSongKey contract.
    var songKey: String
    var songTitle: String
    var seguesIntoNext: Bool
}

/// A full setlist grouped into sets, in stage order.
nonisolated struct Setlist: Sendable, Hashable {
    var showID: String
    var status: CatalogShow.SetlistStatus
    var sets: [SetGroup]

    nonisolated struct SetGroup: Sendable, Hashable, Identifiable {
        var label: String
        var entries: [SetlistEntry]
        var id: String { label }
    }

    init(showID: String, status: CatalogShow.SetlistStatus, entries: [SetlistEntry]) {
        self.showID = showID
        self.status = status
        var groups: [SetGroup] = []
        for entry in entries.sorted(by: { $0.position < $1.position }) {
            if let last = groups.indices.last, groups[last].label == entry.setLabel {
                groups[last].entries.append(entry)
            } else {
                groups.append(SetGroup(label: entry.setLabel, entries: [entry]))
            }
        }
        sets = groups
    }
}

nonisolated struct SongStats: Sendable, Hashable {
    var songKey: String
    var title: String
    var timesPlayed: Int
    var firstPlayed: String?
    var lastPlayed: String?
}

/// Build-time consensus digest of a show's archive.org reviews.
nonisolated struct ShowDigest: Sendable, Hashable {
    var showID: String
    var consensusSummary: String
    var standoutSongs: [String]
    var sentiment: String
    var derivedRating: Double
    var ratingRationale: String
}

nonisolated struct VenueSummary: Sendable, Hashable, Identifiable {
    var venue: String
    var city: String?
    var showCount: Int
    var id: String { venue + (city ?? "") }
}
