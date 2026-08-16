import Foundation

// Internet Archive JSON is loosely typed: the same field arrives as a string,
// an array of strings, or a number depending on the item. These wrappers
// absorb that so the rest of the app sees clean optionals.

nonisolated enum IAFlexible {
    /// Decodes String | [String] (first element) | Int | Double -> String?
    static func string<K: CodingKey>(from container: KeyedDecodingContainer<K>, key: K) -> String? {
        stringValue(in: container, key: key)
    }

    private static func stringValue<K: CodingKey>(in c: KeyedDecodingContainer<K>, key: K) -> String? {
        if let s = try? c.decode(String.self, forKey: key) { return s }
        if let arr = try? c.decode([String].self, forKey: key) { return arr.first }
        if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
        if let d = try? c.decode(Double.self, forKey: key) { return String(d) }
        return nil
    }

    static func double<K: CodingKey>(in c: KeyedDecodingContainer<K>, key: K) -> Double? {
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let i = try? c.decode(Int.self, forKey: key) { return Double(i) }
        if let s = stringValue(in: c, key: key) { return Double(s) }
        return nil
    }

    static func int<K: CodingKey>(in c: KeyedDecodingContainer<K>, key: K) -> Int? {
        if let i = try? c.decode(Int.self, forKey: key) { return i }
        if let d = try? c.decode(Double.self, forKey: key) { return Int(d) }
        if let s = stringValue(in: c, key: key) { return Int(s) }
        return nil
    }
}

// MARK: - advancedsearch.php

nonisolated struct IASearchResponse: Decodable, Sendable {
    var response: Body

    nonisolated struct Body: Decodable, Sendable {
        var numFound: Int
        var docs: [IASearchDoc]
    }
}

nonisolated struct IASearchDoc: Decodable, Sendable {
    var identifier: String
    var title: String?
    var date: String?
    var venue: String?
    var coverage: String?
    var year: Int?
    var avgRating: Double?
    var numReviews: Int?
    var downloads: Int?
    var source: String?

    nonisolated enum CodingKeys: String, CodingKey {
        case identifier, title, date, venue, coverage, year, source, downloads
        case avgRating = "avg_rating"
        case numReviews = "num_reviews"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(String.self, forKey: .identifier)
        title = IAFlexible.string(from: c, key: .title)
        date = IAFlexible.string(from: c, key: .date)
        venue = IAFlexible.string(from: c, key: .venue)
        coverage = IAFlexible.string(from: c, key: .coverage)
        year = IAFlexible.int(in: c, key: .year)
        avgRating = IAFlexible.double(in: c, key: .avgRating)
        numReviews = IAFlexible.int(in: c, key: .numReviews)
        downloads = IAFlexible.int(in: c, key: .downloads)
        source = IAFlexible.string(from: c, key: .source)
    }
}

// MARK: - /metadata/{identifier}

nonisolated struct IAMetadataResponse: Decodable, Sendable {
    var files: [IAFile]?
    var metadata: IAItemMetadata?
    var reviews: [IAReview]?
}

nonisolated struct IAFile: Decodable, Sendable {
    var name: String
    var format: String?
    var title: String?
    var track: String?
    var length: String?

    nonisolated enum CodingKeys: String, CodingKey { case name, format, title, track, length }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        format = IAFlexible.string(from: c, key: .format)
        title = IAFlexible.string(from: c, key: .title)
        track = IAFlexible.string(from: c, key: .track)
        length = IAFlexible.string(from: c, key: .length)
    }

    /// "mm:ss", "hh:mm:ss", or decimal seconds ("432.18") -> seconds.
    var durationSeconds: Double? {
        guard let length, !length.isEmpty else { return nil }
        if let plain = Double(length) { return plain }
        let parts = length.split(separator: ":").map(String.init)
        guard parts.allSatisfy({ Double($0) != nil }), !parts.isEmpty else { return nil }
        return parts.reversed().enumerated().reduce(0.0) { acc, pair in
            acc + (Double(pair.element) ?? 0) * pow(60.0, Double(pair.offset))
        }
    }

    /// Leading integer of the track field: "01" -> 1, "1/2" -> 1.
    var trackNumber: Int? {
        guard let track else { return nil }
        let digits = track.prefix(while: \.isNumber)
        return Int(digits)
    }
}

nonisolated struct IAItemMetadata: Decodable, Sendable {
    var title: String?
    var date: String?
    var venue: String?
    var coverage: String?
    var source: String?
    var lineage: String?
    var notes: String?
    var setlist: String?

    nonisolated enum CodingKeys: String, CodingKey {
        case title, date, venue, coverage, source, lineage, notes, setlist
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = IAFlexible.string(from: c, key: .title)
        date = IAFlexible.string(from: c, key: .date)
        venue = IAFlexible.string(from: c, key: .venue)
        coverage = IAFlexible.string(from: c, key: .coverage)
        source = IAFlexible.string(from: c, key: .source)
        lineage = IAFlexible.string(from: c, key: .lineage)
        // notes / setlist arrive as string OR array of strings
        notes = Self.joined(in: c, key: .notes)
        setlist = Self.joined(in: c, key: .setlist)
    }

    private static func joined(in c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
        if let arr = try? c.decode([String].self, forKey: key) {
            return arr.joined(separator: "\n")
        }
        return IAFlexible.string(from: c, key: key)
    }
}

nonisolated struct IAReview: Decodable, Sendable {
    var reviewtitle: String?
    var reviewbody: String?
    var stars: Double?
    var reviewer: String?
    var reviewdate: String?

    nonisolated enum CodingKeys: String, CodingKey { case reviewtitle, reviewbody, stars, reviewer, reviewdate }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reviewtitle = IAFlexible.string(from: c, key: .reviewtitle)
        reviewbody = IAFlexible.string(from: c, key: .reviewbody)
        stars = IAFlexible.double(in: c, key: .stars)
        reviewer = IAFlexible.string(from: c, key: .reviewer)
        reviewdate = IAFlexible.string(from: c, key: .reviewdate)
    }
}

// MARK: - Date parsing

nonisolated enum IADates {
    private static let isoFull: DateFormatter = makeFormatter("yyyy-MM-dd'T'HH:mm:ss'Z'")
    private static let bare: DateFormatter = makeFormatter("yyyy-MM-dd")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    /// Lenient parse; rejects placeholder dates like "1970-00-00".
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.contains("-00") { return nil }
        if let d = isoFull.date(from: raw) { return d }
        let bareString = String(raw.prefix(10))
        return bare.date(from: bareString)
    }

    /// "1977-05-08" from a raw archive date.
    static func normalizedDayString(_ raw: String?) -> String? {
        guard let raw, raw.count >= 10 else { return nil }
        let s = String(raw.prefix(10))
        return s.contains("-00") ? nil : s
    }
}
