import Foundation
import SwiftData

/// Records listening events and keeps the taste profile up to date.
@Observable
final class HistoryStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = container.mainContext
    }

    func record(show: Show, track: Track, seconds: Double, completed: Bool) {
        let event = ListeningEvent(
            showIdentifier: show.identifier,
            showDisplayName: show.shortName,
            trackTitle: track.title,
            songKey: track.songKey,
            showYear: show.year,
            venue: show.venue,
            secondsListened: seconds,
            completed: completed
        )
        context.insert(event)
        try? context.save()
        recomputeTasteProfile()
    }

    func recentEvents(limit: Int = 50) -> [ListeningEvent] {
        var descriptor = FetchDescriptor<ListeningEvent>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Most recent distinct shows, newest first.
    func recentShows(limit: Int = 10) -> [(identifier: String, displayName: String, lastPlayed: Date)] {
        var seen = Set<String>()
        var result: [(String, String, Date)] = []
        for event in recentEvents(limit: 200) {
            if seen.insert(event.showIdentifier).inserted {
                result.append((event.showIdentifier, event.showDisplayName, event.startedAt))
                if result.count == limit { break }
            }
        }
        return result
    }

    /// What's rising in the rotation, for the smart-collection planner.
    func trendSnapshot(now: Date = .now) -> ListeningTrend {
        TrendEngine.compute(events: recentEvents(limit: 500).map(TrendEngine.Event.init), now: now)
    }

    // MARK: - Taste profile

    private(set) var tasteSnapshot: TasteSnapshot = .empty

    func loadTasteProfile() {
        let descriptor = FetchDescriptor<TasteProfileRecord>()
        if let record = try? context.fetch(descriptor).first,
           let snapshot = try? JSONDecoder().decode(TasteSnapshot.self, from: record.payload) {
            tasteSnapshot = snapshot
        }
    }

    func recomputeTasteProfile() {
        let events = (try? context.fetch(FetchDescriptor<ListeningEvent>())) ?? []
        let snapshot = TasteEngine.recompute(events: events.map(TasteEngine.EventFacts.init))
        tasteSnapshot = snapshot
        guard let payload = try? JSONEncoder().encode(snapshot) else { return }
        let descriptor = FetchDescriptor<TasteProfileRecord>()
        if let record = try? context.fetch(descriptor).first {
            record.payload = payload
            record.lastUpdated = .now
        } else {
            context.insert(TasteProfileRecord(payload: payload))
        }
        try? context.save()
    }
}

/// Pure taste computation — testable without SwiftData.
nonisolated enum TasteEngine {

    nonisolated struct EventFacts: Sendable {
        var songKey: String
        var showIdentifier: String
        var showYear: Int?
        var venue: String?
        var seconds: Double

        init(songKey: String, showIdentifier: String, showYear: Int?, venue: String?, seconds: Double) {
            self.songKey = songKey
            self.showIdentifier = showIdentifier
            self.showYear = showYear
            self.venue = venue
            self.seconds = seconds
        }
    }

    static func recompute(events: [EventFacts]) -> TasteSnapshot {
        guard !events.isEmpty else { return .empty }

        var songSeconds: [String: Double] = [:]
        var venueSeconds: [String: Double] = [:]
        var eraSeconds: [String: Double] = [:]
        var years = Set<Int>()
        var shows = Set<String>()
        var total = 0.0

        for event in events {
            total += event.seconds
            shows.insert(event.showIdentifier)
            if !event.songKey.isEmpty {
                songSeconds[event.songKey, default: 0] += event.seconds
            }
            if let venue = event.venue, !venue.isEmpty {
                venueSeconds[venue, default: 0] += event.seconds
            }
            if let year = event.showYear {
                years.insert(year)
                eraSeconds[eraID(forYear: year), default: 0] += event.seconds
            }
        }

        let eraTotal = max(eraSeconds.values.reduce(0, +), 1)
        let eraWeights = eraSeconds.mapValues { $0 / eraTotal }

        return TasteSnapshot(
            eraWeights: eraWeights,
            topSongKeys: songSeconds.sorted { $0.value > $1.value }.prefix(10).map(\.key),
            favoriteVenues: venueSeconds.sorted { $0.value > $1.value }.prefix(5).map(\.key),
            totalSeconds: total,
            showsHeard: shows.count,
            exploredYears: years.sorted()
        )
    }

    static func eraID(forYear year: Int) -> String {
        switch year {
        case ..<1968: return "primal"
        case 1968...1970: return "anthem"
        case 1971...1974: return "europe-wall"
        case 1975...1977: return "hiatus-return"
        case 1978...1979: return "transition"
        case 1980...1990: return "brent"
        default: return "vince"
        }
    }
}

extension TrendEngine.Event {
    // MainActor-isolated (module default): reads fields off a SwiftData model.
    init(_ event: ListeningEvent) {
        self.init(songKey: event.songKey,
                  showIdentifier: event.showIdentifier,
                  showYear: event.showYear,
                  startedAt: event.startedAt,
                  seconds: event.secondsListened)
    }
}

extension TasteEngine.EventFacts {
    // MainActor-isolated (module default): reads fields off a SwiftData model.
    init(_ event: ListeningEvent) {
        self.init(songKey: event.songKey,
                  showIdentifier: event.showIdentifier,
                  showYear: event.showYear,
                  venue: event.venue,
                  seconds: event.secondsListened)
    }
}
