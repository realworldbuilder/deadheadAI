import Foundation

/// Deterministic, offline AI provider built on the bundled knowledge base.
/// The whole app works with this alone; an OpenAI key only upgrades the prose.
final class LocalKnowledgeAI: AIProvider {
    let name = "Offline Brain"
    private let kb: KnowledgeBase

    init(knowledgeBase: KnowledgeBase) {
        self.kb = knowledgeBase
    }

    // MARK: - Intent parsing

    nonisolated private static let moodTags: [(keywords: [String], tags: [String])] = [
        (["exhausted", "tired", "chill", "relax", "mellow", "rainy", "sunday", "quiet", "sleep", "calm", "gentle"], ["mellow", "acoustic", "ballad"]),
        (["hope", "hopeful", "uplift", "joy", "happy", "sunshine", "celebrat"], ["joyful"]),
        (["dark", "terrifying", "scary", "haunting", "heavy", "menac"], ["dark"]),
        (["psychedelic", "trippy", "space", "spacey", "weird", "melt"], ["psychedelic", "exploratory"]),
        (["primal", "raw", "wild", "garage"], ["primal", "raw"]),
        (["jazz", "jazzy", "complex"], ["jazzy", "exploratory"]),
        (["road trip", "driving", "drive", "highway", "party", "dance", "energy", "energetic", "hot", "cook", "rip"], ["high-energy"]),
        (["beginner", "new to", "start", "first show", "where do i", "gateway"], ["beginner-friendly"]),
        (["jam", "jams", "long", "epic", "deep", "explore", "exploratory"], ["epic-jams", "exploratory"]),
        (["acoustic", "unplugged"], ["acoustic"]),
        (["blues", "pigpen"], ["blues", "primal"]),
        (["tight", "precise", "clean"], ["tight"]),
    ]

    nonisolated static func tags(inQuery query: String) -> Set<String> {
        let lower = query.lowercased()
        var result = Set<String>()
        for entry in moodTags where entry.keywords.contains(where: lower.contains) {
            result.formUnion(entry.tags)
        }
        return result
    }

    nonisolated static func years(inQuery query: String) -> ClosedRange<Int>? {
        let lower = query.lowercased()
        // Full years: 1965...1995
        let fullYears = lower.matches(of: /19[6-9][0-9]/).compactMap { Int($0.output) }
            .filter { (1965...1995).contains($0) }
        if let lo = fullYears.min(), let hi = fullYears.max() { return lo...hi }
        // Shorthand '77 or "77"
        let shortYears = lower.matches(of: /'([6-9][0-9])/).compactMap { Int($0.output.1) }
            .map { $0 + 1900 }
            .filter { (1965...1995).contains($0) }
        if let lo = shortYears.min(), let hi = shortYears.max() { return lo...hi }
        // Decades
        if lower.contains("60s") || lower.contains("sixties") { return 1965...1969 }
        if lower.contains("70s") || lower.contains("seventies") { return 1970...1979 }
        if lower.contains("80s") || lower.contains("eighties") { return 1980...1989 }
        if lower.contains("90s") || lower.contains("nineties") { return 1990...1995 }
        return nil
    }

    private static let knownVenues = [
        "winterland", "fillmore", "barton", "cornell", "veneta", "red rocks",
        "madison square garden", "msg", "nassau", "greek", "boston garden",
        "hampton", "alpine", "shoreline", "soldier field", "rfk", "roosevelt",
    ]

    func parseSearchIntent(_ text: String) async throws -> SearchFilters {
        let lower = text.lowercased()
        var filters = SearchFilters()
        filters.yearRange = Self.years(inQuery: text)
        if let venue = Self.knownVenues.first(where: lower.contains) {
            filters.venueText = venue == "msg" ? "madison square garden" : venue
        }
        if lower.contains("soundboard") || lower.contains("sbd") { filters.soundboardOnly = true }
        if lower.contains("best") || lower.contains("greatest") || lower.contains("top") {
            filters.sortByRating = true
            filters.minRating = 4.0
        }
        if let song = kb.song(matching: text) ?? Self.songMention(in: text, kb: kb) {
            filters.songText = song.title
        }
        // Era names → year ranges.
        if filters.yearRange == nil {
            if lower.contains("europe") { filters.yearRange = 1972...1972 }
            else if lower.contains("wall of sound") { filters.yearRange = 1974...1974 }
            else if lower.contains("brent") { filters.yearRange = 1980...1990 }
            else if lower.contains("pigpen") { filters.yearRange = 1966...1972 }
            else if lower.contains("primal") { filters.yearRange = 1966...1970 }
        }
        return filters
    }

    /// Finds a song title mentioned inside a longer sentence.
    nonisolated static func songMention(in text: String, kb: KnowledgeBase) -> SongInfo? {
        let needle = Track.normalizeSongKey(text)
        return kb.songs
            .filter { needle.contains($0.key) }
            .max { $0.key.count < $1.key.count }
    }

    // MARK: - Recommendation

    func recommend(query: String?, profile: TasteSnapshot, candidates: [Show]) async throws -> Recommendation {
        let queryTags = query.map(Self.tags(inQuery:)) ?? []

        // Score candidates by KB affinity with the query and taste.
        func score(_ show: Show) -> Double {
            var s = RecordingRanker.score(show) * 0.2
            guard let day = show.dateString, let notable = kb.notableShow(on: day) else { return s }
            s += 3   // canon bonus
            s += Double(Set(notable.tags).intersection(queryTags).count) * 4
            s += (profile.eraWeights[notable.eraID] ?? 0) * 2
            if profile.totalSeconds < 1800, notable.tags.contains("beginner-friendly") { s += 2 }
            return s
        }
        guard let pick = candidates.max(by: { score($0) < score($1) }) else {
            throw AIError.noCandidates
        }

        let notable = pick.dateString.flatMap(kb.notableShow(on:))
        let era = notable.flatMap { kb.era(id: $0.eraID) }

        var narrative: [String] = []
        if let query, !query.isEmpty {
            narrative.append(Self.openingLine(forTags: Self.tags(inQuery: query)))
        } else if profile.totalSeconds > 1800, let strongest = profile.eraWeights.max(by: { $0.value < $1.value })?.key,
                  let strongEra = kb.era(id: strongest) {
            narrative.append("You've been living in \(strongEra.name) lately — tonight, here's a night that rewards that ear.")
        } else {
            narrative.append("Here's tonight's pick from the vault.")
        }
        if let notable {
            narrative.append(notable.blurb)
        } else {
            narrative.append("A \(pick.year.map(String.init) ?? "classic")-era night at \(pick.venue ?? "a storied room"), well loved by the community\(pick.avgRating.map { String(format: " (%.1f stars)", $0) } ?? "").")
        }
        if let era {
            narrative.append("It sits in \(era.name) (\(era.years)): \(era.style)")
        }

        let listenFor = notable?.standoutSongs ?? []
        return Recommendation(
            chosenIdentifier: pick.identifier,
            narrative: narrative.joined(separator: " "),
            hook: notable.map { "From \(kb.era(id: $0.eraID)?.name ?? "the vault") — \($0.venue)" }
                ?? "\(pick.displayDate) — \(pick.venue ?? "from the vault")",
            listenFor: listenFor
        )
    }

    nonisolated private static func openingLine(forTags tags: Set<String>) -> String {
        if tags.contains("mellow") { return "Sounds like a night for something gentle — here's where I'd land." }
        if tags.contains("dark") { return "You want the deep end. Good. Bring a flashlight." }
        if tags.contains("psychedelic") { return "Strap in — this one leaves the map entirely." }
        if tags.contains("high-energy") { return "You want fire. This one never lets up." }
        if tags.contains("beginner-friendly") { return "Perfect place to start — welcoming, warm, and unmistakably them." }
        if tags.contains("primal") { return "Back to the garage — loud, raw, and gloriously unpolished." }
        if tags.contains("jazzy") { return "For the conversation between the instruments, start here." }
        return "Here's where I'd point you tonight."
    }

    // MARK: - Smart collections

    func curateCollection(brief: CollectionBrief, candidates: [CollectionCandidate]) async throws -> CuratedCollection {
        guard !candidates.isEmpty else { throw AIError.noCandidates }
        return SmartCollectionCurator.curate(brief: brief, candidates: candidates)
    }

    // MARK: - Show guide

    func showGuide(for detail: RecordingDetail, show: Show?) async throws -> ShowGuide {
        let day = detail.dateString ?? show?.dateString
        let notable = day.flatMap(kb.notableShow(on:))
        let year = day.flatMap { Int($0.prefix(4)) }
        let era = notable.flatMap { kb.era(id: $0.eraID) } ?? year.flatMap(kb.era(forYear:))

        let songKeys = detail.tracks.map(\.songKey)
        let jamVehicles: Set<String> = ["dark star", "playin' in the band", "playin in the band",
                                        "the other one", "eyes of the world", "terrapin station", "space", "drums"]
        let jamCount = songKeys.filter { key in jamVehicles.contains(where: key.contains) }.count

        var improv = 3
        if let era {
            switch era.id {
            case "europe-wall", "anthem": improv = 4
            case "primal": improv = 3
            default: improv = 3
            }
        }
        if jamCount >= 2 { improv = min(improv + 1, 5) }

        // Highlights: KB famous versions on this date, then standouts, then longest tracks.
        var highlights: [String] = []
        if let day {
            for song in kb.songs {
                if let famous = song.famousVersions.first(where: { $0.date == day }) {
                    highlights.append("\(song.title) — \(famous.label ?? "famous version"): \(famous.note)")
                }
            }
        }
        if highlights.isEmpty, let notable {
            highlights = notable.standoutSongs
        }
        if highlights.isEmpty {
            highlights = detail.tracks.sorted { ($0.durationSeconds ?? 0) > ($1.durationSeconds ?? 0) }
                .prefix(3).map(\.title)
        }

        // Transitions: consecutive tracks that are known segue partners.
        var transitions: [String] = []
        for (a, b) in zip(detail.tracks, detail.tracks.dropFirst()) {
            if let info = kb.song(forKey: a.songKey), info.seguePartners.contains(b.songKey) {
                transitions.append("\(a.title) > \(b.title)")
            }
        }

        let stars = detail.reviews.compactMap(\.stars)
        let avgStars = stars.isEmpty ? nil : stars.reduce(0, +) / Double(stars.count)
        var consensus = "Not many reviews on this source yet — sometimes that means a sleeper."
        if let avgStars, detail.reviews.count >= 3 {
            let tone = avgStars >= 4.5 ? "beloved" : avgStars >= 3.8 ? "well regarded" : "debated"
            consensus = String(format: "%d community reviews averaging %.1f stars — a %@ tape.",
                               detail.reviews.count, avgStars, tone)
            if let top = detail.reviews.first(where: { ($0.body?.count ?? 0) > 40 })?.body?.prefix(140) {
                consensus += " One listener put it: “\(String(top).trimmingCharacters(in: .whitespacesAndNewlines))…”"
            }
        }

        let sourceLower = ((detail.source ?? "") + " " + (show?.identifier ?? detail.identifier)).lowercased()
        let isSBD = sourceLower.contains("sbd") || sourceLower.contains("soundboard") || sourceLower.contains("matrix")
        let recordingNotes = isSBD
            ? "Soundboard lineage — clean instrument separation, the band as the crew heard them."
            : "Audience tape — you trade fidelity for the room: crowd roar, hall echo, the actual night."

        return ShowGuide(
            overallMood: notable.map(Self.mood(from:)) ?? era.map { "A night of \($0.style.lowercased().trimmingCharacters(in: .punctuationCharacters))" } ?? "A night with the Grateful Dead",
            historicalContext: [notable?.blurb, era.map { "\($0.name) (\($0.years)): \($0.context)" }]
                .compactMap(\.self).joined(separator: " "),
            musicalHighlights: highlights,
            bestTransitions: transitions,
            improvisationRating: improv,
            accessibility: (notable?.tags.contains("beginner-friendly") ?? false)
                ? "A welcoming entry point — melodic, well recorded, and easy to love on first listen."
                : "Better once you've got a few shows under your belt; the rewards are deeper in.",
            recordingNotes: recordingNotes,
            listenFor: notable?.standoutSongs ?? highlights,
            fanConsensus: consensus,
            recommendedTracks: notable?.standoutSongs ?? Array(highlights.prefix(3))
        )
    }

    nonisolated private static func mood(from show: NotableShow) -> String {
        var parts: [String] = []
        if show.tags.contains("mellow") { parts.append("unhurried") }
        if show.tags.contains("high-energy") { parts.append("blazing") }
        if show.tags.contains("psychedelic") { parts.append("deep-space") }
        if show.tags.contains("joyful") { parts.append("joyous") }
        if show.tags.contains("dark") { parts.append("shadowed") }
        if show.tags.contains("primal") || show.tags.contains("raw") { parts.append("feral") }
        if show.tags.contains("tight") { parts.append("locked-in") }
        if parts.isEmpty { parts.append("classic") }
        return parts.joined(separator: ", ").capitalized
    }

    // MARK: - Chat

    func chatReply(messages: [ChatTurn], grounding: GroundingContext) async throws -> AsyncThrowingStream<String, any Error> {
        let question = messages.last(where: { $0.role == .user })?.text ?? ""
        let sentences = composeChatAnswer(question: question, grounding: grounding)
        return AsyncThrowingStream { continuation in
            let task = Task {
                for sentence in sentences {
                    try? await Task.sleep(for: .milliseconds(120))
                    continuation.yield(sentence + " ")
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func composeChatAnswer(question: String, grounding: GroundingContext) -> [String] {
        let lower = question.lowercased()
        var out: [String] = []

        // Song question?
        if let song = kb.song(matching: question) ?? Self.songMention(in: question, kb: kb) {
            out.append("Ah, \(ChatLink.song(song.key, label: song.title)) — good taste.")
            out.append(song.evolution)
            if let first = song.famousVersions.first {
                out.append("If you only hear one version, make it \(Self.showLink(first.date, kb: kb)): \(first.note)")
            }
            if song.famousVersions.count > 1 {
                let rest = song.famousVersions.dropFirst().map { "\(Self.showLink($0.date, kb: kb)) (\($0.label ?? "essential"))" }
                out.append("Then chase down \(rest.joined(separator: ", ")).")
            }
            return out
        }

        // Era / year question?
        if let years = Self.years(inQuery: question), let era = kb.era(forYear: years.lowerBound) {
            out.append("\(ChatLink.era(era.id, label: era.name)) — \(era.years).")
            out.append(era.summary)
            out.append(era.context)
            let picks = kb.shows(inEra: era.id).prefix(3)
            if !picks.isEmpty {
                out.append("Start with " + picks.map { "\(Self.showLink($0.date, kb: kb)) at \($0.venue)" }.joined(separator: ", then ") + ".")
            }
            return out
        }
        for era in kb.eras where lower.contains(era.name.lowercased()) || lower.contains(era.id) {
            out.append("\(ChatLink.era(era.id, label: era.name)) — \(era.years).")
            out.append(era.summary)
            let picks = kb.shows(inEra: era.id).prefix(3)
            if !picks.isEmpty {
                out.append("Start with " + picks.map { Self.showLink($0.date, kb: kb) }.joined(separator: ", then ") + ".")
            }
            return out
        }
        if lower.contains("wall of sound") {
            out.append("The Wall of Sound was the band's 1974 mega-PA: over 600 speakers, the band mixing themselves onstage, every instrument with its own column of sound.")
            out.append("It was glorious and unsustainable — hauling it broke the crew and the budget, and it pushed the band into the 1975 hiatus.")
            out.append("To hear it: \(Self.showLink("1974-05-19", kb: kb)), \(Self.showLink("1974-06-18", kb: kb)), or the Winterland farewell \(Self.showLink("1974-10-18", kb: kb)) that October.")
            return out
        }

        // Specific notable show mentioned?
        for show in kb.notableShows {
            let venueLower = show.venue.lowercased()
            if lower.contains(venueLower) || lower.contains(show.date) ||
                (venueLower.contains("cornell") && lower.contains("cornell")) ||
                (show.location.lowercased().contains("veneta") && lower.contains("veneta")) {
                out.append("\(ChatLink.show(show.date, label: "\(Self.prettyDate(show.date)), \(show.venue)")), \(show.location).")
                out.append(show.blurb)
                out.append("Listen for: \(show.standoutSongs.joined(separator: ", ")).")
                let related = kb.related(to: show, limit: 2)
                if !related.isEmpty {
                    out.append("If that one lands, go next to " + related.map { Self.showLink($0.date, kb: kb) }.joined(separator: " or ") + ".")
                }
                return out
            }
        }

        // Recommendation-style question?
        let tags = Self.tags(inQuery: question)
        if !tags.isEmpty {
            let picks = kb.shows(matchingTags: tags, limit: 3)
            if !picks.isEmpty {
                out.append(Self.openingLine(forTags: tags))
                for pick in picks {
                    out.append("\(ChatLink.show(pick.date, label: "\(Self.prettyDate(pick.date)) at \(pick.venue)")): \(pick.blurb)")
                }
                return out
            }
        }

        // Fallback.
        if let nowPlaying = grounding.nowPlaying {
            out.append("While \(nowPlaying) plays — here's a thought.")
        }
        out.append("I live for questions like this.")
        out.append("Ask me about a song (\"What's the best Dark Star?\"), a year (\"What made 1973 special?\"), a show (\"Why do people love Veneta?\"), or a mood (\"I need something mellow\").")
        out.append("Or just tell me how you're feeling and I'll pull the right tape.")
        return out
    }

    /// Show link labeled with venue when the KB knows the night.
    nonisolated static func showLink(_ date: String, kb: KnowledgeBase) -> String {
        let label = kb.notableShow(on: date).map { "\(prettyDate(date)) \($0.venue)" } ?? prettyDate(date)
        return ChatLink.show(date, label: label)
    }

    nonisolated static func prettyDate(_ raw: String) -> String {
        guard let date = IADates.parse(raw) else { return raw }
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}

nonisolated enum AIError: Error {
    case missingKey
    case rateLimited
    case badResponse
    case noCandidates
}
