import Foundation

nonisolated enum ArchiveError: Error {
    case badURL
    case decoding(Error)
    case noPlayableTracks
}

/// Thin client over archive.org's advancedsearch + metadata APIs.
nonisolated struct ArchiveAPIClient: Sendable {
    let http: any HTTPClient

    init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    private static let searchFields = [
        "identifier", "title", "date", "venue", "coverage", "year",
        "avg_rating", "num_reviews", "downloads", "source",
    ]

    // MARK: - Search

    /// Runs an advancedsearch query scoped to collection:GratefulDead.
    func searchShows(query: String, rows: Int = 100, page: Int = 1,
                     sort: String = "date asc") async throws -> [Show] {
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: "collection:GratefulDead AND \(query)"),
            URLQueryItem(name: "rows", value: String(rows)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "sort[]", value: sort),
        ]
        items.append(contentsOf: Self.searchFields.map { URLQueryItem(name: "fl[]", value: $0) })
        components.queryItems = items
        guard let url = components.url else { throw ArchiveError.badURL }

        let data = try await http.get(url)
        let decoded: IASearchResponse
        do {
            decoded = try JSONDecoder().decode(IASearchResponse.self, from: data)
        } catch {
            throw ArchiveError.decoding(error)
        }
        return decoded.response.docs.compactMap(Self.show(from:))
    }

    /// All recordings of one show date, e.g. "1977-05-08".
    func recordings(forDate day: String) async throws -> [Show] {
        try await searchShows(query: "date:\(day)", rows: 50, sort: "downloads desc")
    }

    /// Backslash-escapes Lucene query syntax so user-derived text can't break
    /// (or steer) the archive query. Spaces stay intact for phrase matching.
    nonisolated static func luceneEscaped(_ text: String) -> String {
        let specials: Set<Character> = ["+", "-", "!", "(", ")", "{", "}", "[", "]",
                                        "^", "\"", "~", "*", "?", ":", "\\", "/", "&", "|"]
        return String(text.flatMap { specials.contains($0) ? ["\\", $0] : [$0] })
    }

    /// Builds the Lucene query for parsed natural-language filters.
    /// Year/rating bounds are app-generated numbers; only free text is escaped.
    nonisolated static func searchQuery(filters: SearchFilters) -> String {
        var clauses: [String] = []
        if let range = filters.yearRange {
            clauses.append("year:[\(range.lowerBound) TO \(range.upperBound)]")
        }
        if let venue = filters.venueText, !venue.isEmpty {
            let venue = luceneEscaped(venue)
            clauses.append("(venue:(\(venue)) OR coverage:(\(venue)) OR title:(\(venue)))")
        }
        if let text = filters.freeText, !text.isEmpty {
            clauses.append("(\(luceneEscaped(text)))")
        }
        if let rating = filters.minRating {
            clauses.append("avg_rating:[\(rating) TO 5]")
        }
        if clauses.isEmpty { clauses.append("avg_rating:[4.5 TO 5]") }
        return clauses.joined(separator: " AND ")
    }

    /// Query built from parsed natural-language filters.
    func search(filters: SearchFilters, rows: Int = 60) async throws -> [Show] {
        let sort = (filters.sortByRating ?? true) ? "avg_rating desc" : "date asc"
        var shows = try await searchShows(query: Self.searchQuery(filters: filters), rows: rows, sort: sort)
        if let monthDay = filters.monthDay {
            shows = shows.filter { ($0.dateString ?? "").hasSuffix(monthDay) }
        }
        if filters.soundboardOnly == true {
            shows = shows.filter(\.isSoundboard)
        }
        return shows
    }

    // MARK: - Metadata

    func recordingDetail(identifier: String) async throws -> RecordingDetail {
        guard let url = URL(string: "https://archive.org/metadata/\(identifier)") else {
            throw ArchiveError.badURL
        }
        let data = try await http.get(url)
        let decoded: IAMetadataResponse
        do {
            decoded = try JSONDecoder().decode(IAMetadataResponse.self, from: data)
        } catch {
            throw ArchiveError.decoding(error)
        }
        return Self.detail(identifier: identifier, from: decoded)
    }

    // MARK: - Streaming URLs

    nonisolated static func streamURL(identifier: String, fileName: String) -> URL? {
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        return URL(string: "https://archive.org/download/\(identifier)/\(encoded)")
    }

    // MARK: - Mapping

    nonisolated static func show(from doc: IASearchDoc) -> Show? {
        let dayString = IADates.normalizedDayString(doc.date)
        // Items with unparseable dates are almost always non-show ephemera; drop them.
        guard dayString != nil || doc.date == nil else { return nil }
        return Show(
            identifier: doc.identifier,
            title: doc.title ?? doc.identifier,
            date: IADates.parse(doc.date),
            dateString: dayString,
            venue: doc.venue,
            location: doc.coverage,
            year: doc.year ?? dayString.flatMap { Int($0.prefix(4)) },
            avgRating: doc.avgRating,
            numReviews: doc.numReviews,
            downloads: doc.downloads,
            source: doc.source
        )
    }

    /// Best available MP3s, one format only so tracks never duplicate.
    /// Most Dead items carry VBR MP3, but some older transfers offer only
    /// fixed-bitrate MP3s — those are still perfectly streamable.
    nonisolated static let mp3FormatPreference = ["vbr mp3", "128kbps mp3", "64kbps mp3"]

    nonisolated static func playableFiles(in files: [IAFile]) -> [IAFile] {
        for format in mp3FormatPreference {
            let matches = files.filter { ($0.format ?? "").lowercased() == format }
            if !matches.isEmpty { return matches }
        }
        // Last resort: anything the archive calls an MP3 with an .mp3 extension.
        return files.filter {
            ($0.format ?? "").lowercased().contains("mp3") && $0.name.lowercased().hasSuffix(".mp3")
        }
    }

    nonisolated static func detail(identifier: String, from response: IAMetadataResponse) -> RecordingDetail {
        let files = response.files ?? []
        var tracks: [Track] = playableFiles(in: files)
            .map { file in
                Track(
                    fileName: file.name,
                    title: file.title ?? Self.titleFromFileName(file.name),
                    trackNumber: file.trackNumber,
                    durationSeconds: file.durationSeconds
                )
            }
        tracks.sort { a, b in
            switch (a.trackNumber, b.trackNumber) {
            case let (x?, y?) where x != y: return x < y
            case (.some, .none): return true
            case (.none, .some): return false
            default: return a.fileName < b.fileName
            }
        }

        let reviews = (response.reviews ?? []).map { r in
            Review(title: r.reviewtitle, body: r.reviewbody, stars: r.stars,
                   reviewer: r.reviewer, dateString: r.reviewdate)
        }

        let md = response.metadata
        return RecordingDetail(
            identifier: identifier,
            title: md?.title,
            dateString: IADates.normalizedDayString(md?.date),
            venue: md?.venue,
            location: md?.coverage,
            source: md?.source,
            lineage: md?.lineage,
            notes: md?.notes,
            setlistText: md?.setlist,
            tracks: tracks,
            reviews: reviews
        )
    }

    nonisolated static func titleFromFileName(_ name: String) -> String {
        var base = (name as NSString).deletingPathExtension
        if let range = base.range(of: #"^gd\d{2,4}-\d{2}-\d{2}[a-z0-9.]*(d\d+)?t\d+[. ]?"#,
                                  options: .regularExpression) {
            base = String(base[range.upperBound...])
        }
        base = base.replacingOccurrences(of: "_", with: " ")
        return base.isEmpty ? name : base
    }
}

// MARK: - Recording ranking

nonisolated enum RecordingRanker {
    /// Deterministic community-informed quality score. Higher is better.
    static func score(_ show: Show) -> Double {
        var score = 0.0
        if show.isSoundboard { score += 3.0 }
        let haystack = (show.identifier + " " + (show.source ?? "")).lowercased()
        if haystack.contains("matrix") { score += 0.5 }
        if show.isMillerTransfer { score += 1.5 }
        score += 1.0 * (show.avgRating ?? 2.5)
        score += 0.6 * log10(Double(show.downloads ?? 0) + 1)
        score += 0.3 * log10(Double(show.numReviews ?? 0) + 1)
        return score
    }

    /// Best-first; ties broken by identifier for stable ordering.
    static func rank(_ shows: [Show]) -> [Show] {
        shows.sorted { a, b in
            let sa = score(a), sb = score(b)
            if sa != sb { return sa > sb }
            return a.identifier < b.identifier
        }
    }
}
