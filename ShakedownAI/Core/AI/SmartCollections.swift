import Foundation

// Smart collections are shelves the app builds for itself: the planner turns
// "what time is it, what day is it, what has this listener been playing" into
// grounded briefs, and an AI provider names and curates each one. Everything in
// this file is pure and deterministic so it can be tested without a network.

// MARK: - Time context

/// The moment a shelf is built for. Two contexts with the same `key` should
/// produce the same shelves, which is what makes caching honest.
nonisolated struct DayContext: Sendable, Hashable, Codable {
    var year: Int
    var month: Int
    var day: Int
    /// 1 = Sunday, matching `Calendar`.
    var weekday: Int
    var hour: Int
    var dayOfYear: Int

    init(date: Date = .now, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday, .hour], from: date)
        year = parts.year ?? 1970
        month = parts.month ?? 1
        day = parts.day ?? 1
        weekday = parts.weekday ?? 1
        hour = parts.hour ?? 12
        dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
    }

    nonisolated enum Daypart: String, Sendable, Codable {
        case morning, afternoon, evening, lateNight
    }

    nonisolated enum Season: String, Sendable, Codable {
        case winter, spring, summer, fall
    }

    var daypart: Daypart {
        switch hour {
        case 5..<11: return .morning
        case 11..<17: return .afternoon
        case 17..<22: return .evening
        default: return .lateNight
        }
    }

    var season: Season {
        switch month {
        case 12, 1, 2: return .winter
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        default: return .fall
        }
    }

    var isWeekend: Bool { weekday == 1 || weekday == 7 }

    /// "08-16" — used to match anniversaries against the knowledge base.
    var monthDay: String { String(format: "%02d-%02d", month, day) }

    var weekdayName: String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][max(0, min(6, weekday - 1))]
    }

    /// Shelves regenerate when this changes: a new day, or a new part of the day.
    var key: String { String(format: "%04d-%02d-%02d|%@", year, month, day, daypart.rawValue) }
}

// MARK: - Listening trends

/// What's moving in the listener's rotation — the "trend" half of the input.
nonisolated struct ListeningTrend: Sendable, Hashable, Codable {
    /// Songs played more in the last two weeks than in the month before that.
    var risingSongKeys: [String]
    var risingEraID: String?
    /// Show dates heard in the last month, so shelves don't re-serve them.
    var recentDates: Set<String>
    var recentSeconds: Double

    static let empty = ListeningTrend(risingSongKeys: [], risingEraID: nil, recentDates: [], recentSeconds: 0)
}

/// Pure trend computation — testable without SwiftData.
nonisolated enum TrendEngine {

    nonisolated struct Event: Sendable {
        var songKey: String
        var showIdentifier: String
        var showYear: Int?
        var startedAt: Date
        var seconds: Double

        init(songKey: String, showIdentifier: String, showYear: Int?, startedAt: Date, seconds: Double) {
            self.songKey = songKey
            self.showIdentifier = showIdentifier
            self.showYear = showYear
            self.startedAt = startedAt
            self.seconds = seconds
        }
    }

    static let recentWindow: TimeInterval = 14 * 24 * 3600
    static let priorWindow: TimeInterval = 45 * 24 * 3600

    static func compute(events: [Event], now: Date = .now) -> ListeningTrend {
        guard !events.isEmpty else { return .empty }
        let recentCutoff = now.addingTimeInterval(-recentWindow)
        let priorCutoff = now.addingTimeInterval(-priorWindow)

        var recentSongs: [String: Double] = [:]
        var priorSongs: [String: Double] = [:]
        var recentEras: [String: Double] = [:]
        var priorEras: [String: Double] = [:]
        var recentDates = Set<String>()
        var recentSeconds = 0.0

        for event in events {
            let era = event.showYear.map(TasteEngine.eraID(forYear:))
            if event.startedAt >= recentCutoff {
                recentSeconds += event.seconds
                if !event.songKey.isEmpty { recentSongs[event.songKey, default: 0] += event.seconds }
                if let era { recentEras[era, default: 0] += event.seconds }
                if let date = showDate(inIdentifier: event.showIdentifier) { recentDates.insert(date) }
            } else if event.startedAt >= priorCutoff {
                if !event.songKey.isEmpty { priorSongs[event.songKey, default: 0] += event.seconds }
                if let era { priorEras[era, default: 0] += event.seconds }
            }
        }

        // Rising = meaningfully more airtime lately than before.
        func rising(_ recent: [String: Double], _ prior: [String: Double]) -> [String] {
            recent
                .filter { key, seconds in seconds >= 240 && seconds > (prior[key] ?? 0) * 1.2 }
                .sorted { $0.value > $1.value }
                .map(\.key)
        }

        return ListeningTrend(
            risingSongKeys: Array(rising(recentSongs, priorSongs).prefix(5)),
            risingEraID: rising(recentEras, priorEras).first ?? recentEras.max(by: { $0.value < $1.value })?.key,
            recentDates: recentDates,
            recentSeconds: recentSeconds
        )
    }

    /// Archive identifiers carry the show date ("gd1977-05-08.sbd.hicks…").
    static func showDate(inIdentifier identifier: String) -> String? {
        guard let match = identifier.firstMatch(of: /(19[6-9][0-9])-([01][0-9])-([0-3][0-9])/) else { return nil }
        return String(match.output.0)
    }
}

// MARK: - Briefs

/// A shelf the app has decided to build, before the AI names it. The rationale
/// is the honest reason — it becomes the prompt, and the fallback blurb.
nonisolated struct CollectionBrief: Sendable, Hashable, Codable, Identifiable {
    var slotID: String
    var badge: String
    var fallbackTitle: String
    var iconName: String
    var rationale: String
    var tags: [String]
    /// Knowledge-base show dates offered to the curator.
    var candidateDates: [String]
    /// Set when the shelf should pull live archive results instead of the canon.
    var archiveQuery: ArchiveQuery?

    var id: String { slotID }

    nonisolated struct ArchiveQuery: Sendable, Hashable, Codable {
        var yearStart: Int?
        var yearEnd: Int?
        var limit: Int

        var yearRange: ClosedRange<Int>? {
            guard let yearStart else { return nil }
            return yearStart...max(yearEnd ?? yearStart, yearStart)
        }
    }
}

/// One show offered to the curator, flattened into everything it may cite.
nonisolated struct CollectionCandidate: Sendable, Hashable, Codable {
    var date: String
    var venue: String
    var location: String
    var eraName: String?
    var tags: [String]
    var blurb: String
    var standoutSongs: [String]
    /// Present when the candidate came from a live archive query.
    var identifier: String?
    var rating: Double?

    var displayTitle: String {
        let pretty = LocalKnowledgeAI.prettyDate(date)
        return venue.isEmpty ? pretty : "\(pretty) — \(venue)"
    }
}

/// The AI's answer: a name, a reason, and an ordered pick list.
nonisolated struct CuratedCollection: Codable, Hashable, Sendable {
    var title: String
    var blurb: String
    var badge: String
    var picks: [Pick]

    nonisolated struct Pick: Codable, Hashable, Sendable {
        var date: String
        var note: String
    }
}

// MARK: - The finished shelf

nonisolated struct SmartCollectionItem: Codable, Hashable, Identifiable, Sendable {
    var date: String
    var title: String
    var subtitle: String
    /// Resolved archive identifier when the shelf already knows one.
    var identifier: String?
    var note: String

    var id: String { identifier ?? date }
}

nonisolated struct SmartCollection: Codable, Hashable, Identifiable, Sendable {
    var slotID: String
    var title: String
    var blurb: String
    var badge: String
    var iconName: String
    var items: [SmartCollectionItem]
    var generatedAt: Date
    var contextKey: String
    /// Which brain named it — "OpenAI" or "Offline Brain".
    var curatedBy: String

    var id: String { slotID }
}

// MARK: - Planner

/// Turns the clock, the calendar, and the listener's trends into briefs.
nonisolated struct SmartCollectionPlanner: Sendable {
    let knowledgeBase: KnowledgeBase

    init(knowledgeBase: KnowledgeBase) {
        self.knowledgeBase = knowledgeBase
    }

    func briefs(context: DayContext, taste: TasteSnapshot, trend: ListeningTrend) -> [CollectionBrief] {
        let drafts = [
            daypartBrief(context: context, taste: taste, trend: trend),
            calendarBrief(context: context, taste: taste, trend: trend),
            trendBrief(context: context, taste: taste, trend: trend),
            deepCutBrief(context: context, taste: taste, trend: trend),
        ].compactMap(\.self)

        // No show appears on two shelves the same day.
        var claimed = Set<String>()
        var result: [CollectionBrief] = []
        for var brief in drafts {
            brief.candidateDates = brief.candidateDates.filter { claimed.insert($0).inserted }
            guard brief.candidateDates.count >= 3 || brief.archiveQuery != nil else { continue }
            result.append(brief)
        }
        return result
    }

    // MARK: Slot 1 — the clock

    private func daypartBrief(context: DayContext, taste: TasteSnapshot, trend: ListeningTrend) -> CollectionBrief? {
        let recipe: (title: String, badge: String, icon: String, tags: [String], why: String)
        switch (context.daypart, context.weekday) {
        case (.morning, 1):
            recipe = ("Slow Sunday", "SUNDAY MORNING", "sun.horizon.fill", ["mellow", "acoustic", "ballad"],
                      "It's Sunday morning — slow starts, acoustic sets, and the gentlest Jerry ballads in the canon.")
        case (.morning, 2):
            recipe = ("Monday Ignition", "MONDAY MORNING", "bolt.fill", ["high-energy", "joyful", "tight"],
                      "Monday morning needs a push: first sets that come out of the gate hot.")
        case (.morning, _):
            recipe = ("First Light", "THIS MORNING", "sun.horizon.fill", ["mellow", "joyful", "acoustic"],
                      "Morning listening — warm, melodic, nothing that demands the whole room yet.")
        case (.afternoon, 1), (.afternoon, 7):
            recipe = ("Backyard Speakers", "WEEKEND AFTERNOON", "guitars.fill", ["joyful", "high-energy", "beginner-friendly"],
                      "A weekend afternoon: outdoor shows and daylight sets meant to be played loud with the door open.")
        case (.afternoon, _):
            recipe = ("Afternoon Drift", "THIS AFTERNOON", "waveform", ["exploratory", "jazzy", "mellow"],
                      "Working hours — jams that reward half your attention and reveal themselves on the second pass.")
        case (.evening, 6):
            recipe = ("Friday Night Fire", "FRIDAY NIGHT", "flame.fill", ["high-energy", "tight", "joyful"],
                      "It's Friday night. These are the nights the band came out swinging and never let up.")
        case (.evening, 7):
            recipe = ("Saturday Blowout", "SATURDAY NIGHT", "flame.fill", ["high-energy", "epic-jams", "joyful"],
                      "Saturday night: the big rooms, the long second sets, the encores that ran late.")
        case (.evening, _):
            recipe = ("Tonight's Deep End", "TONIGHT", "guitars.fill", ["exploratory", "epic-jams", "psychedelic"],
                      "A weeknight with room to stretch — shows that take their time getting where they're going.")
        case (.lateNight, _):
            recipe = ("The Small Hours", "LATE NIGHT", "moon.stars.fill", ["psychedelic", "exploratory", "dark"],
                      "Everyone else is asleep. This is when Dark Star, Space, and the strange stuff belong.")
        }

        let dates = select(tags: recipe.tags, limit: 6, rotation: context.dayOfYear,
                           taste: taste, excluding: trend.recentDates)
        return CollectionBrief(slotID: "daypart", badge: recipe.badge, fallbackTitle: recipe.title,
                               iconName: recipe.icon, rationale: recipe.why, tags: recipe.tags,
                               candidateDates: dates, archiveQuery: nil)
    }

    // MARK: Slot 2 — the calendar

    private func calendarBrief(context: DayContext, taste: TasteSnapshot, trend: ListeningTrend) -> CollectionBrief? {
        // Anniversaries first: nights the band actually played on this date.
        let anniversaries = knowledgeBase.showsOn(monthDay: context.monthDay)
        if !anniversaries.isEmpty {
            var dates = anniversaries.map(\.date)
            // Pad with the closest relatives so the shelf isn't a single card.
            for show in anniversaries {
                dates.append(contentsOf: knowledgeBase.related(to: show, limit: 3).map(\.date))
            }
            let years = anniversaries.compactMap(\.year).map(String.init).joined(separator: ", ")
            return CollectionBrief(
                slotID: "calendar",
                badge: "ON THIS DAY",
                fallbackTitle: "Anniversary Nights",
                iconName: "calendar",
                rationale: "The Dead played this date in \(years). These are those nights, plus the shows they lead to.",
                tags: [],
                candidateDates: Array(dates.uniqued().prefix(6)),
                archiveQuery: nil
            )
        }

        // Then song anniversaries: a debut that happened on this calendar day.
        if let song = knowledgeBase.songs.first(where: { ($0.debut?.dropFirst(5)).map(String.init) == context.monthDay }),
           let debut = song.debut {
            var dates = song.famousVersions.map(\.date)
            dates.append(debut)
            dates.append(contentsOf: knowledgeBase.notableShows
                .filter { $0.standoutSongs.contains { Track.normalizeSongKey($0) == song.key } }
                .map(\.date))
            let unique = dates.uniqued()
                .filter { knowledgeBase.notableShow(on: $0) != nil || $0 == debut }
            return CollectionBrief(
                slotID: "calendar",
                badge: "DEBUT ANNIVERSARY",
                fallbackTitle: "\(song.title): Then and After",
                iconName: "calendar",
                rationale: "\(song.title) debuted on this day, \(LocalKnowledgeAI.prettyDate(debut)). \(song.evolution)",
                tags: [],
                candidateDates: Array(unique.prefix(6)),
                archiveQuery: nil
            )
        }

        // Otherwise the season — tour cycles are the Dead's real calendar.
        let recipe: (title: String, badge: String, months: Set<Int>, why: String)
        switch context.season {
        case .winter:
            recipe = ("Winter Tapes", "WINTER RUNS", [12, 1, 2],
                      "Winter meant indoor runs and the New Year's shows — cold outside, hot inside.")
        case .spring:
            recipe = ("Spring Tour", "SPRING TOUR", [3, 4, 5],
                      "Spring tour: the band coming off rehearsals sharp, playing the college halls.")
        case .summer:
            recipe = ("Summer Outdoors", "SUMMER TOUR", [6, 7, 8],
                      "Summer meant fields, sheds, and daylight — shows that sound like the weather they were played in.")
        case .fall:
            recipe = ("Fall Tour", "FALL TOUR", [9, 10, 11],
                      "Fall tour, the season the band did their most restless playing.")
        }
        let dates = select(tags: [], months: recipe.months, limit: 6,
                           rotation: context.dayOfYear, taste: taste, excluding: trend.recentDates)
        return CollectionBrief(slotID: "calendar", badge: recipe.badge, fallbackTitle: recipe.title,
                               iconName: "calendar", rationale: recipe.why, tags: [],
                               candidateDates: dates, archiveQuery: nil)
    }

    // MARK: Slot 3 — trends

    private func trendBrief(context: DayContext, taste: TasteSnapshot, trend: ListeningTrend) -> CollectionBrief? {
        // A song climbing in the listener's own rotation.
        if let key = trend.risingSongKeys.first, let song = knowledgeBase.song(forKey: key) {
            var dates = song.famousVersions.map(\.date)
            dates.append(contentsOf: knowledgeBase.notableShows
                .filter { $0.standoutSongs.contains { Track.normalizeSongKey($0) == song.key } }
                .map(\.date))
            let unique = dates.uniqued().filter { !trend.recentDates.contains($0) }
            if unique.count >= 3 {
                return CollectionBrief(
                    slotID: "trend",
                    badge: "RISING IN YOUR ROTATION",
                    fallbackTitle: "More \(song.title)",
                    iconName: "chart.line.uptrend.xyaxis",
                    rationale: "\(song.title) is climbing in your listening these past two weeks. Here's where that song goes deepest.",
                    tags: song.tags,
                    candidateDates: Array(unique.prefix(6)),
                    archiveQuery: nil
                )
            }
        }

        // Otherwise an era they're sinking into — unheard nights only.
        if let eraID = trend.risingEraID ?? taste.eraWeights.max(by: { $0.value < $1.value })?.key,
           let era = knowledgeBase.era(id: eraID) {
            let dates = knowledgeBase.shows(inEra: eraID)
                .map(\.date)
                .filter { !trend.recentDates.contains($0) }
            if dates.count >= 3 {
                let rotated = rotate(dates, by: context.dayOfYear, limit: 6)
                return CollectionBrief(
                    slotID: "trend",
                    badge: "WHERE YOU'VE BEEN LIVING",
                    fallbackTitle: "Deeper into \(era.name)",
                    iconName: "chart.line.uptrend.xyaxis",
                    rationale: "You've been spending your time in \(era.name) (\(era.years)). \(era.style) These are the nights you haven't heard yet.",
                    tags: [],
                    candidateDates: rotated,
                    archiveQuery: nil
                )
            }
        }

        // New listener: fall back to what the whole community keeps reaching for.
        let decade = [(1969, 1974), (1975, 1979), (1980, 1990)][context.dayOfYear % 3]
        return CollectionBrief(
            slotID: "trend",
            badge: "WHAT THE ARCHIVE LOVES",
            fallbackTitle: "Most-Loved Tapes",
            iconName: "chart.line.uptrend.xyaxis",
            rationale: "The recordings other listeners rate and stream the most, \(decade.0)–\(decade.1). Not the canon — the crowd.",
            tags: [],
            candidateDates: [],
            archiveQuery: .init(yearStart: decade.0, yearEnd: decade.1, limit: 8)
        )
    }

    // MARK: Slot 4 — the rotating deep cut

    private static let deepCuts: [(title: String, badge: String, icon: String, tags: [String], why: String)] = [
        ("Deep Space", "DEEP CUT", "sparkles", ["psychedelic", "exploratory"],
         "The nights the band left the map entirely and didn't hurry back."),
        ("Pigpen's Barroom", "DEEP CUT", "guitars.fill", ["primal", "raw", "blues"],
         "Before the cosmos, there was a bar band with an organ player who could testify."),
        ("The Jazz Ear", "DEEP CUT", "waveform", ["jazzy", "exploratory"],
         "For when you want to hear five people having a conversation instead of playing songs."),
        ("The Long Ones", "DEEP CUT", "infinity", ["epic-jams"],
         "Nothing under fifteen minutes. Clear your evening."),
        ("Pure Joy", "DEEP CUT", "sun.horizon.fill", ["joyful", "tight"],
         "Shows where you can hear the band grinning."),
        ("Shadow Sets", "DEEP CUT", "moon.stars.fill", ["dark"],
         "The heavy nights — menace, minor keys, and Jerry singing about weather."),
        ("Gentle Hands", "DEEP CUT", "heart.fill", ["mellow", "ballad", "acoustic"],
         "Quiet playing from a band famous for the opposite."),
        ("The On-Ramp", "DEEP CUT", "car.fill", ["beginner-friendly"],
         "If someone asked you where to start tomorrow, you'd hand them these."),
    ]

    private func deepCutBrief(context: DayContext, taste: TasteSnapshot, trend: ListeningTrend) -> CollectionBrief? {
        let recipe = Self.deepCuts[context.dayOfYear % Self.deepCuts.count]
        let dates = select(tags: recipe.tags, limit: 6, rotation: context.dayOfYear / Self.deepCuts.count,
                           taste: taste, excluding: trend.recentDates)
        return CollectionBrief(slotID: "deep-cut", badge: "\(recipe.badge) · \(context.weekdayName.uppercased())",
                               fallbackTitle: recipe.title, iconName: recipe.icon,
                               rationale: recipe.why, tags: recipe.tags,
                               candidateDates: dates, archiveQuery: nil)
    }

    // MARK: Candidate selection

    /// Scores the canon against the brief's tags and the listener's eras, then
    /// rotates the window so the same shelf serves different shows tomorrow.
    func select(tags: [String], months: Set<Int> = [], limit: Int,
                rotation: Int, taste: TasteSnapshot, excluding: Set<String>) -> [String] {
        let wanted = Set(tags)
        var scored: [(date: String, score: Double)] = []
        for show in knowledgeBase.notableShows {
            if !months.isEmpty {
                guard let month = Int(show.date.dropFirst(5).prefix(2)), months.contains(month) else { continue }
            }
            var score = wanted.isEmpty ? 1.0 : Double(Set(show.tags).intersection(wanted).count) * 2.0
            guard score > 0 else { continue }
            score += (taste.eraWeights[show.eraID] ?? 0) * 2.0
            if excluding.contains(show.date) { score -= 3.0 }
            scored.append((show.date, score))
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.date < rhs.date
        }
        let pool = scored.prefix(max(limit * 2, 10)).map(\.date)
        return rotate(pool, by: rotation, limit: limit)
    }

    private func rotate(_ dates: [String], by rotation: Int, limit: Int) -> [String] {
        guard dates.count > limit else { return dates }
        let start = ((rotation % dates.count) + dates.count) % dates.count
        return (0..<limit).map { dates[(start + $0) % dates.count] }
    }

    /// Flattens knowledge-base dates into curator candidates.
    func candidates(forDates dates: [String]) -> [CollectionCandidate] {
        dates.compactMap { date in
            guard let show = knowledgeBase.notableShow(on: date) else { return nil }
            return CollectionCandidate(
                date: show.date,
                venue: show.venue,
                location: show.location,
                eraName: knowledgeBase.era(id: show.eraID)?.name,
                tags: show.tags,
                blurb: show.blurb,
                standoutSongs: show.standoutSongs,
                identifier: show.preferredIdentifier,
                rating: nil
            )
        }
    }

    /// Flattens live archive results into curator candidates.
    func candidates(forShows shows: [Show]) -> [CollectionCandidate] {
        shows.compactMap { show in
            guard let date = show.dateString else { return nil }
            let notable = knowledgeBase.notableShow(on: date)
            return CollectionCandidate(
                date: date,
                venue: show.venue ?? notable?.venue ?? "",
                location: show.location ?? notable?.location ?? "",
                eraName: show.year.flatMap { knowledgeBase.era(forYear: $0)?.name },
                tags: notable?.tags ?? [],
                blurb: notable?.blurb ?? "",
                standoutSongs: notable?.standoutSongs ?? [],
                identifier: show.identifier,
                rating: show.avgRating
            )
        }
    }
}

// MARK: - Deterministic curation (the offline curator)

/// Names and orders a shelf without a network. `LocalKnowledgeAI` uses this,
/// and it's the guaranteed floor when a remote curator misbehaves.
nonisolated enum SmartCollectionCurator {

    static func curate(brief: CollectionBrief, candidates: [CollectionCandidate], limit: Int = 5) -> CuratedCollection {
        let picks = candidates.prefix(limit).map {
            CuratedCollection.Pick(date: $0.date, note: note(for: $0))
        }
        return CuratedCollection(title: brief.fallbackTitle,
                                 blurb: brief.rationale,
                                 badge: brief.badge,
                                 picks: Array(picks))
    }

    static func note(for candidate: CollectionCandidate) -> String {
        if let song = candidate.standoutSongs.first, !song.isEmpty {
            return "Listen for \(song)."
        }
        if !candidate.blurb.isEmpty {
            return firstSentence(candidate.blurb)
        }
        if let rating = candidate.rating {
            return String(format: "%.1f stars from the community.", rating)
        }
        return candidate.location.isEmpty ? "A night worth the time." : "Live from \(candidate.location)."
    }

    static func firstSentence(_ text: String) -> String {
        guard let end = text.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) else { return text }
        return String(text[...end])
    }
}

// MARK: - Helpers

extension Array where Element: Hashable {
    /// Order-preserving dedupe.
    nonisolated func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
