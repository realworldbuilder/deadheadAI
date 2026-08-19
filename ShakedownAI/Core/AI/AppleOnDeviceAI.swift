import Foundation

/// Guard rails for answers coming back from a small model. Deliberately outside
/// the Foundation Models availability gate so they stay unit-testable on any
/// simulator, and because the failure modes they cover — a candidate number
/// out of range, "none" typed into an optional string — are not Apple-specific.
nonisolated enum OnDeviceAnswer {
    /// Maps a 1-based candidate number from the model onto a valid array index.
    static func clampIndex(_ number: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(number - 1, 0), count - 1)
    }

    /// Small models answer an unknown optional with "", " ", or "none" rather
    /// than leaving it out.
    static func nilIfBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.lowercased() != "none" else { return nil }
        return trimmed
    }

    /// A streamed snapshot taken before the first real token, which the
    /// framework renders as the literal string "null".
    static func isPlaceholder(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "null"
    }

    /// Drops any line naming a song the knowledge base never offered. A 3B
    /// model will happily invent Dead songs ("Carefree/Comin' Back to Earth"),
    /// and the app promises it never invents.
    ///
    /// With nothing to check against, or when filtering would leave the list
    /// empty, we fall back to the curated songs for the chosen show rather than
    /// showing the listener nothing.
    static func grounded(_ lines: [String], in knownSongs: Set<String>, fallback: [String]) -> [String] {
        guard !knownSongs.isEmpty else { return lines }
        let lowerKnown = knownSongs.map { $0.lowercased() }
        let kept = lines.filter { line in
            let lowered = line.lowercased()
            return lowerKnown.contains { lowered.contains($0) }
        }
        if !kept.isEmpty { return kept }
        return fallback.isEmpty ? lines : Array(fallback.prefix(3))
    }
}

// Compiled only when the SDK ships Foundation Models (Xcode 26+). Older
// toolchains build the app without this provider and fall back to the offline
// brain, so CI never breaks on a runner with an older Xcode.
#if canImport(FoundationModels)
import FoundationModels

/// Apple's on-device foundation model as an `AIProvider`. Free forever, works
/// offline, needs no key and no account — but it is a ~3B model with a small
/// context window, so every prompt here is tighter than the OpenAI equivalent
/// and the model picks candidates *by number* rather than reproducing archive
/// identifiers verbatim, which small models get wrong.
///
/// Requires iOS 26 on Apple Intelligence hardware. Anything else falls through
/// to `LocalKnowledgeAI` via `CompositeAIProvider`.
@available(iOS 26.0, *)
final class AppleOnDeviceAI: AIProvider {
    let name = "On-device"

    private let kb: KnowledgeBase
    private let archive: ArchiveAPIClient

    init(knowledgeBase: KnowledgeBase, archive: ArchiveAPIClient = ArchiveAPIClient()) {
        self.kb = knowledgeBase
        self.archive = archive
    }

    /// Whether the model can run *right now*: the framework reports hardware
    /// support, Apple Intelligence being switched on, and the weights having
    /// finished downloading. Checked per call, not cached — the user can turn
    /// Apple Intelligence off while the app is running.
    static var isReady: Bool {
        SystemLanguageModel.default.availability == .available
    }

    private static let voice = """
    You are Deadhead AI, a lifelong Grateful Dead companion: warm, curious, \
    encouraging, never robotic. Ground every claim in the data you are given. \
    Never invent shows, dates, or songs that are not in that data. Keep answers \
    short and concrete.
    """

    private func session(tools: [any Tool] = []) -> LanguageModelSession {
        LanguageModelSession(tools: tools, instructions: Self.voice)
    }

    // MARK: - Recommendation

    @Generable
    nonisolated fileprivate struct GeneratedRecommendation {
        @Guide(description: "The number of the chosen show from the candidate list")
        var candidateNumber: Int
        @Guide(description: "3-5 sentences telling the story of why this show, like a trusted friend. Never a list.")
        var narrative: String
        @Guide(description: "One-line hook, under 12 words")
        var hook: String
        @Guide(description: "Moments to listen for. Use ONLY song titles listed under 'songs' for the chosen show.", .count(3))
        var listenFor: [String]
    }

    func recommend(query: String?, profile: TasteSnapshot, candidates: [Show]) async throws -> Recommendation {
        guard Self.isReady else { throw AIError.missingKey }
        guard !candidates.isEmpty else { throw AIError.noCandidates }

        // The context window is ~4k tokens for prompt *and* output, so we offer
        // far fewer candidates than the OpenAI path's 15.
        let offered = Array(candidates.prefix(8))
        // Songs are listed per candidate so the model has a real vocabulary to
        // draw `listenFor` from. Without it a 3B model invents song titles.
        var lines: [String] = []
        var knownSongs: Set<String> = []
        for (index, show) in offered.enumerated() {
            var line = "\(index + 1). \(show.dateString ?? "?") — \(show.displayVenue)"
            if let rating = show.avgRating { line += String(format: " (%.1f)", rating) }
            if let day = show.dateString, let notable = kb.notableShow(on: day) {
                line += " — \(notable.blurb.prefix(120))"
                let songs = notable.standoutSongs.prefix(6)
                if !songs.isEmpty {
                    line += " | songs: \(songs.joined(separator: ", "))"
                    knownSongs.formUnion(songs.map { $0.lowercased() })
                }
            }
            lines.append(line)
        }

        let taste = profile.totalSeconds > 0
            ? "Listener favors: \(profile.topSongKeys.prefix(4).joined(separator: ", ")). \(profile.showsHeard) shows heard."
            : "Listener is new — favor accessible, beloved shows."

        let prompt = """
        \(taste)
        Request: \(query ?? "Pick tonight's show and say why.")

        Candidates:
        \(lines.joined(separator: "\n"))

        Choose one candidate by its number and make the case for it.
        """

        let response = try await session().respond(
            to: prompt,
            generating: GeneratedRecommendation.self,
            options: GenerationOptions(temperature: 0.7, maximumResponseTokens: 600)
        )
        let result = response.content
        let chosen = offered[OnDeviceAnswer.clampIndex(result.candidateNumber, count: offered.count)]
        let chosenSongs = chosen.dateString.flatMap { kb.notableShow(on: $0) }?.standoutSongs ?? []

        return Recommendation(
            chosenIdentifier: chosen.identifier,
            narrative: result.narrative,
            hook: result.hook,
            listenFor: OnDeviceAnswer.grounded(result.listenFor, in: knownSongs, fallback: chosenSongs)
        )
    }

    // MARK: - Show guide

    @Generable
    nonisolated fileprivate struct GeneratedShowGuide {
        @Guide(description: "The overall mood of this performance, one sentence")
        var overallMood: String
        @Guide(description: "Where this show sits in the band's history, 1-2 sentences")
        var historicalContext: String
        @Guide(description: "Standout moments, using only songs from the setlist", .count(2...4))
        var musicalHighlights: [String]
        @Guide(description: "Notable song-to-song transitions from the setlist", .count(1...3))
        var bestTransitions: [String]
        @Guide(description: "How exploratory the playing is, 1 (tight) to 5 (deep space)", .range(1...5))
        var improvisationRating: Int
        @Guide(description: "Who this show suits — newcomer, seasoned head — one sentence")
        var accessibility: String
        @Guide(description: "What the tape itself sounds like, one sentence")
        var recordingNotes: String
        @Guide(description: "Specific things to listen for", .count(2...4))
        var listenFor: [String]
        @Guide(description: "What fans generally say about this show, one sentence")
        var fanConsensus: String
        @Guide(description: "Song titles copied exactly from the setlist", .count(2...4))
        var recommendedTracks: [String]
    }

    func showGuide(for detail: RecordingDetail, show: Show?) async throws -> ShowGuide {
        guard Self.isReady else { throw AIError.missingKey }

        let setlist = detail.tracks.map(\.title).prefix(30).joined(separator: ", ")
        let review = detail.reviews.prefix(2).compactMap(\.body).map { String($0.prefix(200)) }
        let notable = (detail.dateString ?? show?.dateString).flatMap(kb.notableShow(on:))

        let prompt = """
        Build a listening guide. Use ONLY the data below; reference only songs \
        that appear in the setlist.

        Date: \(detail.dateString ?? "unknown") | Venue: \(detail.venue ?? "unknown")
        Source: \(detail.source ?? "unknown")
        Setlist: \(setlist)
        Curator notes: \(notable?.blurb.prefix(200) ?? "none")
        Fan reviews: \(review.joined(separator: " ||| "))
        """

        let response = try await session().respond(
            to: prompt,
            generating: GeneratedShowGuide.self,
            options: GenerationOptions(temperature: 0.6, maximumResponseTokens: 900)
        )
        let g = response.content
        return ShowGuide(
            overallMood: g.overallMood,
            historicalContext: g.historicalContext,
            musicalHighlights: g.musicalHighlights,
            bestTransitions: g.bestTransitions,
            improvisationRating: min(max(g.improvisationRating, 1), 5),
            accessibility: g.accessibility,
            recordingNotes: g.recordingNotes,
            listenFor: g.listenFor,
            fanConsensus: g.fanConsensus,
            recommendedTracks: g.recommendedTracks
        )
    }

    // MARK: - Search intent

    @Generable
    nonisolated fileprivate struct GeneratedSearchFilters {
        @Guide(description: "Earliest year mentioned, between 1965 and 1995, or nothing")
        var yearStart: Int?
        @Guide(description: "Latest year mentioned, between 1965 and 1995, or nothing")
        var yearEnd: Int?
        @Guide(description: "Month and day as MM-DD if the query names a specific calendar date")
        var monthDay: String?
        @Guide(description: "Venue or city named in the query")
        var venueText: String?
        @Guide(description: "Song title named in the query")
        var songText: String?
        @Guide(description: "Minimum community rating from 0 to 5 if the query asks for highly rated shows")
        var minRating: Double?
        // Non-optional deliberately: the model reliably leaves optional Bools
        // empty even when the request plainly asks for soundboards, and false
        // and nil mean the same thing to `ArchiveAPIClient.search`.
        @Guide(description: "True if the request mentions soundboard, SBD, board tapes, or matrix. False otherwise.")
        var soundboardOnly: Bool
    }

    func parseSearchIntent(_ text: String) async throws -> SearchFilters {
        guard Self.isReady else { throw AIError.missingKey }

        let prompt = """
        Extract search filters from this request. Leave a field empty when the \
        request does not mention it — do not guess.

        Request: \(text)
        """

        let response = try await session().respond(
            to: prompt,
            generating: GeneratedSearchFilters.self,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 300)
        )
        let f = response.content

        var filters = SearchFilters()
        if let start = f.yearStart, (1965...1995).contains(start) {
            let end = f.yearEnd.map { min(max($0, start), 1995) } ?? start
            filters.yearRange = start...end
        }
        filters.monthDay = f.monthDay.flatMap { $0.count == 5 ? $0 : nil }
        filters.venueText = OnDeviceAnswer.nilIfBlank(f.venueText)
        filters.songText = OnDeviceAnswer.nilIfBlank(f.songText)
        filters.minRating = f.minRating.map { min(max($0, 0), 5) }
        filters.soundboardOnly = f.soundboardOnly ? true : nil
        filters.sortByRating = true
        return filters
    }

    // MARK: - Smart collection curation

    @Generable
    nonisolated fileprivate struct GeneratedCollection {
        @Guide(description: "Shelf title, 2-5 words, evocative not generic")
        var title: String
        @Guide(description: "One sentence on why these shows belong together")
        var blurb: String
        @Guide(description: "The chosen shows, best first")
        var picks: [GeneratedPick]
    }

    @Generable
    nonisolated fileprivate struct GeneratedPick {
        @Guide(description: "The number of this show in the candidate list")
        var candidateNumber: Int
        @Guide(description: "One short line on why this show earns its place")
        var note: String
    }

    func curateCollection(brief: CollectionBrief, candidates: [CollectionCandidate]) async throws -> CuratedCollection {
        guard Self.isReady else { throw AIError.missingKey }
        guard !candidates.isEmpty else { throw AIError.noCandidates }

        let offered = Array(candidates.prefix(10))
        let lines = offered.enumerated().map { index, candidate -> String in
            var line = "\(index + 1). \(candidate.date) — \(candidate.venue)"
            if !candidate.blurb.isEmpty { line += " — \(candidate.blurb.prefix(100))" }
            return line
        }

        let prompt = """
        Name and fill a shelf of Grateful Dead shows.
        Theme: \(brief.rationale)
        Mood tags: \(brief.tags.prefix(4).joined(separator: ", "))

        Candidates:
        \(lines.joined(separator: "\n"))

        Pick 3 to 5 candidates by number, best first.
        """

        let response = try await session().respond(
            to: prompt,
            generating: GeneratedCollection.self,
            options: GenerationOptions(temperature: 0.8, maximumResponseTokens: 600)
        )
        let result = response.content

        // Map numbers back to real dates and drop repeats — a small model will
        // occasionally pick the same show twice.
        var seen = Set<String>()
        var picks: [CuratedCollection.Pick] = []
        for pick in result.picks {
            let candidate = offered[OnDeviceAnswer.clampIndex(pick.candidateNumber, count: offered.count)]
            guard seen.insert(candidate.date).inserted else { continue }
            picks.append(CuratedCollection.Pick(date: candidate.date, note: pick.note))
        }
        guard !picks.isEmpty else { throw AIError.badResponse }

        return CuratedCollection(
            title: OnDeviceAnswer.nilIfBlank(result.title) ?? brief.fallbackTitle,
            blurb: result.blurb,
            badge: brief.badge,
            picks: picks
        )
    }

    // MARK: - Chat

    func chatReply(messages: [ChatTurn], grounding: GroundingContext) async throws -> AsyncThrowingStream<String, any Error> {
        guard Self.isReady else { throw AIError.missingKey }

        var context: [String] = []
        if let nowPlaying = grounding.nowPlaying { context.append("Now playing: \(nowPlaying)") }
        if !grounding.recentShows.isEmpty {
            context.append("Recently heard: \(grounding.recentShows.prefix(3).joined(separator: "; "))")
        }
        if let taste = grounding.tasteSummary { context.append("Taste: \(taste)") }
        if !grounding.knowledgeSnippets.isEmpty {
            context.append("Notes: " + grounding.knowledgeSnippets.prefix(2).joined(separator: " "))
        }

        // Six turns rather than the OpenAI path's twelve — the window is small
        // and the tool schemas already cost tokens.
        let transcript = messages.suffix(6)
            .map { "\($0.role == .user ? "Listener" : "You"): \($0.text.prefix(400))" }
            .joined(separator: "\n")

        let prompt = """
        Context: \(context.isEmpty ? "none" : context.joined(separator: " | "))

        \(transcript)

        Reply to the listener's last message. Use a tool when you need real show data.
        """

        // The framework runs the tool loop itself — no manual round-tripping.
        let modelSession = session(tools: [
            SearchArchiveTool(archive: archive),
            LookupSongTool(kb: kb),
            BestRecordingTool(archive: archive, kb: kb),
        ])

        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let task = Task { @MainActor in
            do {
                // Snapshots are cumulative, so we emit the delta each time to
                // keep the UI's incremental streaming behaviour.
                var emitted = ""
                for try await snapshot in modelSession.streamResponse(
                    to: prompt,
                    options: GenerationOptions(temperature: 0.8, maximumResponseTokens: 700)
                ) {
                    // Snapshots before the first token arrive as the literal
                    // "null" placeholder; emitting it would print it in the UI.
                    let text = snapshot.content
                    guard !OnDeviceAnswer.isPlaceholder(text) else { continue }
                    if text.hasPrefix(emitted) {
                        let delta = String(text.dropFirst(emitted.count))
                        if !delta.isEmpty { continuation.yield(delta) }
                        emitted = text
                    } else if emitted.isEmpty {
                        continuation.yield(text)
                        emitted = text
                    }
                    // A snapshot that contradicts what we already emitted would
                    // duplicate text in the UI, so it is dropped.
                }
                if emitted.isEmpty { throw AIError.badResponse }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

}

// MARK: - Tools

/// Same three capabilities the OpenAI chat path exposes, expressed as the
/// framework's `Tool` protocol so the session drives the loop itself.
@available(iOS 26.0, *)
nonisolated struct SearchArchiveTool: Tool {
    let name = "search_archive"
    let description = "Search the Internet Archive's Grateful Dead collection for live shows."
    let archive: ArchiveAPIClient

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "Earliest year, 1965-1995")
        var yearStart: Int?
        @Guide(description: "Latest year, 1965-1995")
        var yearEnd: Int?
        @Guide(description: "Venue or city to match")
        var venueText: String?
        @Guide(description: "Minimum community rating, 0-5")
        var minRating: Double?
        @Guide(description: "Only soundboard recordings")
        var soundboardOnly: Bool?
    }

    func call(arguments: Arguments) async throws -> String {
        var filters = SearchFilters()
        if let start = arguments.yearStart {
            filters.yearRange = start...max(arguments.yearEnd ?? start, start)
        }
        filters.venueText = arguments.venueText
        filters.minRating = arguments.minRating
        filters.soundboardOnly = arguments.soundboardOnly
        filters.sortByRating = true

        let shows = (try? await archive.search(filters: filters, rows: 30)) ?? []
        let ranked = RecordingRanker.rank(shows).prefix(5)
        guard !ranked.isEmpty else { return "No shows found. Broaden the search." }
        return ranked.map { show in
            "date=\(show.dateString ?? "?") venue=\(show.displayVenue) rating=\(show.avgRating.map { String(format: "%.1f", $0) } ?? "n/a") sbd=\(show.isSoundboard)"
        }.joined(separator: "\n")
    }
}

@available(iOS 26.0, *)
nonisolated struct LookupSongTool: Tool {
    let name = "lookup_song"
    let description = "Get a song's history, famous versions, and segue partners from the curated knowledge base."
    let kb: KnowledgeBase

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "Song title, e.g. 'Dark Star'")
        var title: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let song = kb.song(matching: arguments.title) else {
            return "Song not found in the knowledge base."
        }
        var lines = ["title=\(song.title)", song.evolution]
        for famous in song.famousVersions.prefix(3) {
            lines.append("famous version date=\(famous.date) note=\(famous.note)")
        }
        if !song.seguePartners.isEmpty {
            lines.append("segue partners: \(song.seguePartners.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}

@available(iOS 26.0, *)
nonisolated struct BestRecordingTool: Tool {
    let name = "best_recording_for_date"
    let description = "Find the best archive recording of a specific show date. Use to verify a show exists before naming it."
    let archive: ArchiveAPIClient
    let kb: KnowledgeBase

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "Show date as YYYY-MM-DD")
        var date: String
    }

    func call(arguments: Arguments) async throws -> String {
        let date = arguments.date
        let recordings = (try? await archive.recordings(forDate: date)) ?? []
        guard let best = RecordingRanker.rank(recordings).first else {
            return "No archive recordings found for \(date)."
        }
        var line = "date=\(date) venue=\(best.displayVenue) identifier=\(best.identifier) sources=\(recordings.count)"
        if let rating = best.avgRating { line += String(format: " rating=%.1f", rating) }
        if let notable = kb.notableShow(on: date) { line += " curatorNote=\(notable.blurb)" }
        return line
    }
}

#endif
