import Foundation

// All domain models are plain Sendable value types, explicitly nonisolated so
// they can be encoded/decoded and manipulated off the main actor.

// MARK: - Shows & recordings

/// One archive.org item (a specific recording of a show).
nonisolated struct Show: Codable, Hashable, Identifiable, Sendable {
    var identifier: String
    var title: String
    var date: Date?
    /// Raw "yyyy-mm-dd" string as it appears in the archive.
    var dateString: String?
    var venue: String?
    /// City/state ("coverage" field).
    var location: String?
    var year: Int?
    var avgRating: Double?
    var numReviews: Int?
    var downloads: Int?
    var source: String?

    var id: String { identifier }

    /// "May 8, 1977" style display date, falling back to the raw string.
    var displayDate: String {
        guard let date else { return dateString ?? "Unknown date" }
        return Self.displayFormatter.string(from: date)
    }

    var displayVenue: String {
        var parts: [String] = []
        if let venue, !venue.isEmpty { parts.append(venue) }
        if let location, !location.isEmpty { parts.append(location) }
        return parts.isEmpty ? "Unknown venue" : parts.joined(separator: " · ")
    }

    var shortName: String {
        if let venue, !venue.isEmpty { return "\(displayDate) — \(venue)" }
        return displayDate
    }

    var isSoundboard: Bool {
        let haystack = (identifier + " " + (source ?? "")).lowercased()
        return haystack.contains("sbd") || haystack.contains("soundboard") || haystack.contains("matrix")
    }

    var isMillerTransfer: Bool {
        (identifier + " " + (source ?? "")).lowercased().contains("miller")
    }

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US")
        return f
    }()
}

/// Full metadata for one recording, from archive.org/metadata/{id}.
nonisolated struct RecordingDetail: Codable, Hashable, Sendable {
    var identifier: String
    var title: String?
    var dateString: String?
    var venue: String?
    var location: String?
    var source: String?
    var lineage: String?
    var notes: String?
    var setlistText: String?
    var tracks: [Track]
    var reviews: [Review]
}

nonisolated struct Track: Codable, Hashable, Identifiable, Sendable {
    /// File name inside the item, e.g. "gd77-05-08d1t01.mp3".
    var fileName: String
    var title: String
    var trackNumber: Int?
    var durationSeconds: Double?

    var id: String { fileName }

    var displayDuration: String {
        guard let durationSeconds, durationSeconds > 0 else { return "--:--" }
        let total = Int(durationSeconds.rounded())
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Normalized song key for taste aggregation: lowercase, no punctuation,
    /// stripped of segue arrows and leading track junk.
    var songKey: String {
        Track.normalizeSongKey(title)
    }

    nonisolated static func normalizeSongKey(_ title: String) -> String {
        var t = title.lowercased()
        for arrow in ["->", ">", "-->"] { t = t.replacingOccurrences(of: arrow, with: "") }
        t = t.replacingOccurrences(of: #"[^a-z' ]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }
}

nonisolated struct Review: Codable, Hashable, Sendable {
    var title: String?
    var body: String?
    var stars: Double?
    var reviewer: String?
    var dateString: String?
}

// MARK: - AI outputs

nonisolated struct Recommendation: Codable, Hashable, Sendable {
    /// Must be one of the candidate identifiers offered to the AI.
    var chosenIdentifier: String
    /// The story: why this show, why now.
    var narrative: String
    /// One-line hook shown on cards.
    var hook: String
    /// What to listen for, in order.
    var listenFor: [String]
}

nonisolated struct ShowGuide: Codable, Hashable, Sendable {
    var overallMood: String
    var historicalContext: String
    var musicalHighlights: [String]
    var bestTransitions: [String]
    var improvisationRating: Int      // 1...5
    var accessibility: String
    var recordingNotes: String
    var listenFor: [String]
    var fanConsensus: String
    var recommendedTracks: [String]
}

nonisolated struct SearchFilters: Codable, Hashable, Sendable {
    var yearRange: ClosedRange<Int>?
    var monthDay: String?          // "05-08"
    var venueText: String?
    var freeText: String?
    var songText: String?
    var minRating: Double?
    var soundboardOnly: Bool?
    var sortByRating: Bool?

    nonisolated enum CodingKeys: String, CodingKey {
        case yearStart, yearEnd, monthDay, venueText, freeText, songText, minRating, soundboardOnly, sortByRating
    }

    init(yearRange: ClosedRange<Int>? = nil, monthDay: String? = nil, venueText: String? = nil,
         freeText: String? = nil, songText: String? = nil, minRating: Double? = nil,
         soundboardOnly: Bool? = nil, sortByRating: Bool? = nil) {
        self.yearRange = yearRange
        self.monthDay = monthDay
        self.venueText = venueText
        self.freeText = freeText
        self.songText = songText
        self.minRating = minRating
        self.soundboardOnly = soundboardOnly
        self.sortByRating = sortByRating
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let start = try c.decodeIfPresent(Int.self, forKey: .yearStart)
        let end = try c.decodeIfPresent(Int.self, forKey: .yearEnd)
        if let start { yearRange = start...(max(end ?? start, start)) }
        monthDay = try c.decodeIfPresent(String.self, forKey: .monthDay)
        venueText = try c.decodeIfPresent(String.self, forKey: .venueText)
        freeText = try c.decodeIfPresent(String.self, forKey: .freeText)
        songText = try c.decodeIfPresent(String.self, forKey: .songText)
        minRating = try c.decodeIfPresent(Double.self, forKey: .minRating)
        soundboardOnly = try c.decodeIfPresent(Bool.self, forKey: .soundboardOnly)
        sortByRating = try c.decodeIfPresent(Bool.self, forKey: .sortByRating)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(yearRange?.lowerBound, forKey: .yearStart)
        try c.encodeIfPresent(yearRange?.upperBound, forKey: .yearEnd)
        try c.encodeIfPresent(monthDay, forKey: .monthDay)
        try c.encodeIfPresent(venueText, forKey: .venueText)
        try c.encodeIfPresent(freeText, forKey: .freeText)
        try c.encodeIfPresent(songText, forKey: .songText)
        try c.encodeIfPresent(minRating, forKey: .minRating)
        try c.encodeIfPresent(soundboardOnly, forKey: .soundboardOnly)
        try c.encodeIfPresent(sortByRating, forKey: .sortByRating)
    }
}

// MARK: - Taste & chat

nonisolated struct TasteSnapshot: Codable, Hashable, Sendable {
    var eraWeights: [String: Double]     // era id -> weight
    var topSongKeys: [String]
    var favoriteVenues: [String]
    var totalSeconds: Double
    var showsHeard: Int
    var exploredYears: [Int]

    static let empty = TasteSnapshot(eraWeights: [:], topSongKeys: [], favoriteVenues: [],
                                     totalSeconds: 0, showsHeard: 0, exploredYears: [])
}

nonisolated struct ChatTurn: Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    var role: Role
    var text: String
}

nonisolated struct GroundingContext: Codable, Hashable, Sendable {
    var nowPlaying: String?
    var recentShows: [String]
    var tasteSummary: String?
    var knowledgeSnippets: [String]

    static let empty = GroundingContext(nowPlaying: nil, recentShows: [], tasteSummary: nil, knowledgeSnippets: [])
}

// MARK: - Knowledge base

nonisolated struct NotableShow: Codable, Hashable, Identifiable, Sendable {
    var date: String                 // "1977-05-08"
    var venue: String
    var location: String
    var eraID: String
    var tags: [String]
    var blurb: String
    var standoutSongs: [String]
    /// Preferred archive identifier if the community favors one source.
    var preferredIdentifier: String?

    var id: String { date }
    var year: Int? { Int(date.prefix(4)) }
    var monthDay: String { String(date.dropFirst(5)) }
}

nonisolated struct SongInfo: Codable, Hashable, Identifiable, Sendable {
    var key: String                  // normalized, e.g. "dark star"
    var title: String
    var writtenBy: String?
    var debut: String?
    var lastPlayed: String?
    var timesPlayed: Int?
    var evolution: String
    var famousVersions: [FamousVersion]
    var seguePartners: [String]
    var tags: [String]

    var id: String { key }

    nonisolated struct FamousVersion: Codable, Hashable, Sendable {
        var date: String
        var note: String
        var label: String?           // "Most emotional", "Best jam"...
    }
}

nonisolated struct EraInfo: Codable, Hashable, Identifiable, Sendable {
    var id: String                   // "primal", "europe72"...
    var name: String
    var years: String                // "1965–1967"
    var startYear: Int
    var endYear: Int
    var lineup: String
    var style: String
    var summary: String
    var beginnerShows: [String]      // dates
    var mustHear: [String]           // dates
    var context: String
}

nonisolated struct Journey: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var days: [JourneyDay]

    nonisolated struct JourneyDay: Codable, Hashable, Sendable {
        var title: String
        var showDate: String         // "1972-08-27"
        var essay: String
        var focusTracks: [String]
        var journalPrompt: String
    }
}

nonisolated struct BandQuote: Codable, Hashable, Sendable {
    var text: String
    var attribution: String
}
