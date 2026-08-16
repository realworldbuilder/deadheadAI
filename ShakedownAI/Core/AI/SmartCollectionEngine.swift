import Foundation

/// Builds the day's shelves: plan from context → gather grounded candidates →
/// let the AI name and order each one → cache. Every step degrades gracefully,
/// so a dead network still produces shelves from the bundled canon.
@Observable
final class SmartCollectionEngine {
    private let env: AppEnvironment
    private let planner: SmartCollectionPlanner

    /// Surfaced so the UI can say why a shelf list looks thin.
    private(set) var lastError: String?

    init(env: AppEnvironment) {
        self.env = env
        self.planner = SmartCollectionPlanner(knowledgeBase: env.knowledgeBase)
    }

    var store: SmartCollectionStore { env.smartCollections }
    var collections: [SmartCollection] { store.collections }
    var isRefreshing: Bool { store.isRefreshing }

    /// One line for the UI: when these shelves were built, and from what.
    var lastGeneratedSummary: String? {
        guard let generated = store.lastGenerated else { return nil }
        return "Rebuilt \(generated.formatted(.relative(presentation: .named))) from the hour, the calendar, and your rotation."
    }

    /// Regenerates only when the day or the daypart has turned over.
    func refreshIfNeeded(now: Date = .now) async {
        let context = DayContext(date: now)
        guard store.needsRefresh(for: context.key) else { return }
        await refresh(now: now)
    }

    func refresh(now: Date = .now) async {
        let context = DayContext(date: now)
        guard store.beginRefresh() else { return }
        defer { store.endRefresh() }

        let taste = env.history.tasteSnapshot
        let trend = env.history.trendSnapshot(now: now)
        let briefs = planner.briefs(context: context, taste: taste, trend: trend)
        guard !briefs.isEmpty else {
            lastError = "No shelves to build — the knowledge base looks empty."
            return
        }

        // Shelves are independent; build them concurrently so a slow curator
        // call doesn't hold up the rest.
        var built: [String: SmartCollection] = [:]
        await withTaskGroup(of: (String, SmartCollection?).self) { group in
            for brief in briefs {
                group.addTask { [self] in
                    (brief.slotID, await build(brief: brief, context: context))
                }
            }
            for await (slotID, collection) in group {
                built[slotID] = collection
            }
        }

        let ordered = briefs.compactMap { built[$0.slotID] ?? nil }
        guard !ordered.isEmpty else {
            lastError = "Couldn't reach the archive to fill today's shelves."
            return
        }
        lastError = nil
        store.replace(with: ordered, contextKey: context.key)
    }

    // MARK: - One shelf

    private func build(brief: CollectionBrief, context: DayContext) async -> SmartCollection? {
        let candidates = await candidates(for: brief)
        guard candidates.count >= 3 else { return nil }

        let curated: CuratedCollection
        let curatedBy: String
        if let remote = try? await env.aiProvider.curateCollection(brief: brief, candidates: candidates),
           remote.picks.count >= 3 {
            curated = remote
            curatedBy = env.aiProvider.name
        } else {
            curated = SmartCollectionCurator.curate(brief: brief, candidates: candidates)
            curatedBy = "Offline Brain"
        }

        let byDate = Dictionary(candidates.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let items: [SmartCollectionItem] = curated.picks.compactMap { pick in
            guard let candidate = byDate[pick.date] else { return nil }   // guardrail: real shows only
            return SmartCollectionItem(
                date: candidate.date,
                title: candidate.displayTitle,
                subtitle: [candidate.location, candidate.eraName].compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " · "),
                identifier: candidate.identifier,
                note: pick.note.isEmpty ? SmartCollectionCurator.note(for: candidate) : pick.note
            )
        }
        guard items.count >= 3 else { return nil }

        return SmartCollection(
            slotID: brief.slotID,
            title: curated.title.isEmpty ? brief.fallbackTitle : curated.title,
            blurb: curated.blurb.isEmpty ? brief.rationale : curated.blurb,
            badge: brief.badge,
            iconName: brief.iconName,
            items: items,
            generatedAt: .now,
            contextKey: context.key,
            curatedBy: curatedBy
        )
    }

    private func candidates(for brief: CollectionBrief) async -> [CollectionCandidate] {
        var candidates = planner.candidates(forDates: brief.candidateDates)
        if let query = brief.archiveQuery {
            let shows = (try? await env.recordingProvider.topRated(yearRange: query.yearRange, limit: query.limit)) ?? []
            // One recording per night, best source first.
            var seenDates = Set<String>()
            let collapsed = RecordingRanker.rank(shows).filter { show in
                guard let date = show.dateString else { return false }
                return seenDates.insert(date).inserted
            }
            candidates.append(contentsOf: planner.candidates(forShows: collapsed))
        }
        return candidates
    }

    // MARK: - Pinning a shelf into the library

    /// Copies a generated shelf into a real, editable collection. Items that
    /// only know their date get resolved to their best archive recording.
    @discardableResult
    func pinToLibrary(_ collection: SmartCollection) async -> ShowCollection {
        let saved = env.library.createCollection(name: collection.title,
                                                 blurb: collection.blurb,
                                                 iconName: collection.iconName)
        for item in collection.items {
            var show: Show?
            if let identifier = item.identifier {
                show = Show(identifier: identifier, title: item.title, date: IADates.parse(item.date),
                            dateString: item.date, venue: item.title, location: nil,
                            year: Int(item.date.prefix(4)), avgRating: nil, numReviews: nil,
                            downloads: nil, source: nil)
            } else {
                show = (try? await env.recordingProvider.recordings(forDate: item.date))?.first
            }
            if let show { env.library.add(show: show, to: saved) }
        }
        return saved
    }
}
