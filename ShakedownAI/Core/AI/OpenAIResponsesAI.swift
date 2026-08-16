import Foundation

/// OpenAI Responses API-backed provider. Grounded prompts only: the model
/// always chooses among real archive candidates and real setlists — it is
/// never asked to recall shows from memory.
final class OpenAIResponsesAI: AIProvider {
    let name = "OpenAI"
    private let kb: KnowledgeBase
    private let archive: ArchiveAPIClient
    private let model = "gpt-4o-mini"

    init(knowledgeBase: KnowledgeBase, archive: ArchiveAPIClient = ArchiveAPIClient()) {
        self.kb = knowledgeBase
        self.archive = archive
    }

    private static let systemVoice = """
    You are Deadhead AI, a lifelong Deadhead companion: warm, curious, encouraging, \
    occasionally funny, never robotic or pretentious. You ground every claim in the \
    provided data — setlists, reviews, and candidate shows. Never invent shows, dates, \
    or setlist entries that are not in the provided data. If unsure, say so plainly.
    """

    // MARK: - Requests

    nonisolated private struct ResponsesRequest: Encodable {
        var model: String
        var instructions: String
        var input: String
        var text: TextFormat?
        var stream: Bool?

        nonisolated struct TextFormat: Encodable {
            var format: Format
            nonisolated struct Format: Encodable {
                var type = "json_schema"
                var name: String
                var schema: JSONValue
                var strict = true
            }
        }
    }

    nonisolated private struct ResponsesReply: Decodable {
        var id: String?
        var output: [OutputItem]?

        nonisolated struct OutputItem: Decodable {
            var type: String?
            var content: [ContentItem]?
            var callId: String?
            var name: String?
            var arguments: String?

            nonisolated enum CodingKeys: String, CodingKey {
                case type, content, name, arguments
                case callId = "call_id"
            }
        }
        nonisolated struct ContentItem: Decodable {
            var type: String?
            var text: String?
        }

        var outputText: String? {
            output?.compactMap { item -> String? in
                guard item.type == "message" else { return nil }
                return item.content?.first(where: { $0.type == "output_text" })?.text
            }.first
        }

        var functionCalls: [OutputItem] {
            output?.filter { $0.type == "function_call" } ?? []
        }
    }

    nonisolated private static func send(_ request: ResponsesRequest, apiKey: String) async throws -> Data {
        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 60
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw AIError.missingKey
        case 429: throw AIError.rateLimited
        default: throw AIError.badResponse
        }
    }

    nonisolated private static func decodeStructured<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let reply = try JSONDecoder().decode(ResponsesReply.self, from: data)
        guard let text = reply.outputText, let payload = text.data(using: .utf8) else {
            throw AIError.badResponse
        }
        return try JSONDecoder().decode(T.self, from: payload)
    }

    private func requireKey() throws -> String {
        guard let key = KeychainStore.resolveAPIKey() else { throw AIError.missingKey }
        return key
    }

    // MARK: - Recommendation

    func recommend(query: String?, profile: TasteSnapshot, candidates: [Show]) async throws -> Recommendation {
        let apiKey = try requireKey()
        guard !candidates.isEmpty else { throw AIError.noCandidates }

        var candidateLines: [String] = []
        for show in candidates.prefix(15) {
            var line = "- identifier: \(show.identifier) | date: \(show.dateString ?? "?") | venue: \(show.displayVenue)"
            if let rating = show.avgRating { line += String(format: " | rating: %.1f", rating) }
            if let day = show.dateString, let notable = kb.notableShow(on: day) {
                line += " | notes: \(notable.blurb) | tags: \(notable.tags.joined(separator: ","))"
            }
            candidateLines.append(line)
        }

        let tasteText = profile.totalSeconds > 0
            ? "Listener taste: top songs \(profile.topSongKeys.prefix(5).joined(separator: ", ")); era weights \(profile.eraWeights.map { "\($0.key)=\(String(format: "%.2f", $0.value))" }.joined(separator: ", ")); \(profile.showsHeard) shows heard."
            : "Listener is new — favor accessible, beloved shows."

        let input = """
        \(tasteText)
        Request: \(query ?? "Pick tonight's show and tell the story of why.")

        Candidate shows (you MUST choose chosenIdentifier from this list, verbatim):
        \(candidateLines.joined(separator: "\n"))

        Respond with a recommendation. The narrative should read like a trusted friend \
        telling a story (3-5 sentences), never a list. listenFor: 2-4 concrete moments.
        """

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "chosenIdentifier": .object(["type": .string("string")]),
                "narrative": .object(["type": .string("string")]),
                "hook": .object(["type": .string("string")]),
                "listenFor": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
            ]),
            "required": .array([.string("chosenIdentifier"), .string("narrative"), .string("hook"), .string("listenFor")]),
            "additionalProperties": .bool(false),
        ])

        let request = ResponsesRequest(
            model: model,
            instructions: Self.systemVoice,
            input: input,
            text: .init(format: .init(name: "recommendation", schema: schema))
        )
        let data = try await Self.send(request, apiKey: apiKey)
        let rec = try Self.decodeStructured(Recommendation.self, from: data)
        // Guardrail: the model must pick a real candidate.
        guard candidates.contains(where: { $0.identifier == rec.chosenIdentifier }) else {
            throw AIError.badResponse
        }
        return rec
    }

    // MARK: - Show guide

    func showGuide(for detail: RecordingDetail, show: Show?) async throws -> ShowGuide {
        let apiKey = try requireKey()
        let setlist = detail.tracks.map(\.title).joined(separator: ", ")
        let reviewSample = detail.reviews.prefix(4).compactMap(\.body).map { String($0.prefix(240)) }
        let notable = (detail.dateString ?? show?.dateString).flatMap(kb.notableShow(on:))

        let input = """
        Build a listening guide for this recording. Use ONLY the data below; only \
        reference songs that appear in the setlist.

        Date: \(detail.dateString ?? "unknown") | Venue: \(detail.venue ?? "unknown"), \(detail.location ?? "")
        Source: \(detail.source ?? "unknown") | Lineage: \(detail.lineage ?? "unknown")
        Setlist: \(setlist)
        Curator notes: \(notable?.blurb ?? "none")
        Community reviews (\(detail.reviews.count) total): \(reviewSample.joined(separator: " ||| "))
        """

        func stringProp() -> JSONValue { .object(["type": .string("string")]) }
        func arrayProp() -> JSONValue { .object(["type": .string("array"), "items": .object(["type": .string("string")])]) }
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "overallMood": stringProp(),
                "historicalContext": stringProp(),
                "musicalHighlights": arrayProp(),
                "bestTransitions": arrayProp(),
                "improvisationRating": .object(["type": .string("integer")]),
                "accessibility": stringProp(),
                "recordingNotes": stringProp(),
                "listenFor": arrayProp(),
                "fanConsensus": stringProp(),
                "recommendedTracks": arrayProp(),
            ]),
            "required": .array([.string("overallMood"), .string("historicalContext"),
                                .string("musicalHighlights"), .string("bestTransitions"),
                                .string("improvisationRating"), .string("accessibility"),
                                .string("recordingNotes"), .string("listenFor"),
                                .string("fanConsensus"), .string("recommendedTracks")]),
            "additionalProperties": .bool(false),
        ])

        let request = ResponsesRequest(
            model: model,
            instructions: Self.systemVoice,
            input: input,
            text: .init(format: .init(name: "show_guide", schema: schema))
        )
        let data = try await Self.send(request, apiKey: apiKey)
        return try Self.decodeStructured(ShowGuide.self, from: data)
    }

    // MARK: - Search intent

    func parseSearchIntent(_ text: String) async throws -> SearchFilters {
        let apiKey = try requireKey()
        let input = """
        Parse this Grateful Dead search request into filters. Years are 1965-1995.
        Request: "\(text)"
        Fields: yearStart/yearEnd (integers or null), venueText (string or null), \
        freeText (string or null — words to full-text match), songText (a song title \
        mentioned, or null), minRating (number or null), soundboardOnly (bool or null), \
        sortByRating (bool or null — true if they asked for "best").
        """
        func nullable(_ type: String) -> JSONValue {
            .object(["type": .array([.string(type), .string("null")])])
        }
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "yearStart": nullable("integer"),
                "yearEnd": nullable("integer"),
                "monthDay": nullable("string"),
                "venueText": nullable("string"),
                "freeText": nullable("string"),
                "songText": nullable("string"),
                "minRating": nullable("number"),
                "soundboardOnly": nullable("boolean"),
                "sortByRating": nullable("boolean"),
            ]),
            "required": .array([.string("yearStart"), .string("yearEnd"), .string("monthDay"),
                                .string("venueText"), .string("freeText"), .string("songText"),
                                .string("minRating"), .string("soundboardOnly"), .string("sortByRating")]),
            "additionalProperties": .bool(false),
        ])
        let request = ResponsesRequest(
            model: model,
            instructions: "You convert natural-language music search queries into structured filters. Output only the JSON.",
            input: input,
            text: .init(format: .init(name: "search_filters", schema: schema))
        )
        let data = try await Self.send(request, apiKey: apiKey)
        return try Self.decodeStructured(SearchFilters.self, from: data)
    }

    // MARK: - Smart collections

    func curateCollection(brief: CollectionBrief, candidates: [CollectionCandidate]) async throws -> CuratedCollection {
        let apiKey = try requireKey()
        guard candidates.count >= 3 else { throw AIError.noCandidates }

        let candidateLines = candidates.prefix(14).map { candidate -> String in
            var line = "- date: \(candidate.date) | venue: \(candidate.venue), \(candidate.location)"
            if let era = candidate.eraName { line += " | era: \(era)" }
            if !candidate.tags.isEmpty { line += " | tags: \(candidate.tags.joined(separator: ","))" }
            if let rating = candidate.rating { line += String(format: " | rating: %.1f", rating) }
            if !candidate.standoutSongs.isEmpty { line += " | standouts: \(candidate.standoutSongs.joined(separator: ", "))" }
            if !candidate.blurb.isEmpty { line += " | notes: \(candidate.blurb)" }
            return line
        }

        let input = """
        Build a themed shelf of Grateful Dead shows for a listener, right now.

        Why this shelf exists (the honest reason — keep the blurb faithful to it):
        \(brief.rationale)

        Working title: \(brief.fallbackTitle)

        Candidate shows (pick 4-5, and every `date` you return MUST appear here verbatim):
        \(candidateLines.joined(separator: "\n"))

        title: 2-4 words, evocative, no colons, not a sentence.
        blurb: one or two sentences saying why these shows, right now — the voice of a \
        friend handing over tapes, never marketing copy.
        badge: 1-3 words in caps describing the occasion.
        picks: ordered best-first. Each note is ONE short sentence about what that \
        specific night gives you — cite only songs or details from that show's data above.
        """

        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "title": .object(["type": .string("string")]),
                "blurb": .object(["type": .string("string")]),
                "badge": .object(["type": .string("string")]),
                "picks": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "date": .object(["type": .string("string")]),
                            "note": .object(["type": .string("string")]),
                        ]),
                        "required": .array([.string("date"), .string("note")]),
                        "additionalProperties": .bool(false),
                    ]),
                ]),
            ]),
            "required": .array([.string("title"), .string("blurb"), .string("badge"), .string("picks")]),
            "additionalProperties": .bool(false),
        ])

        let request = ResponsesRequest(
            model: model,
            instructions: Self.systemVoice,
            input: input,
            text: .init(format: .init(name: "curated_collection", schema: schema))
        )
        let data = try await Self.send(request, apiKey: apiKey)
        var curated = try Self.decodeStructured(CuratedCollection.self, from: data)

        // Guardrail: the model may only shelve shows it was offered.
        let offered = Set(candidates.map(\.date))
        curated.picks = curated.picks.filter { offered.contains($0.date) }
        guard curated.picks.count >= 3 else { throw AIError.badResponse }
        return curated
    }

    // MARK: - Chat (tool-calling loop)

    /// Tools the chatbot can call: live archive search, song lookup, and
    /// best-recording resolution. Replies embed [[show:...]] / [[song:...]] /
    /// [[era:...]] tokens that render as tappable links in the chat.
    private static let chatInstructions = systemVoice + """


    You have tools. Use search_archive to find real shows, lookup_song for song \
    history and famous versions, and best_recording_for_date to confirm a show \
    exists before recommending it. Whenever you recommend or mention a specific \
    show, song, or era, embed a link token so the listener can tap straight to it:
    - Show: [[show:YYYY-MM-DD|label]]  (e.g. [[show:1977-05-08|Cornell 5/8/77]])
    - Song: [[song:lowercase song name|Song Title]]  (e.g. [[song:dark star|Dark Star]])
    - Era: [[era:id|Era Name]] where id is one of primal, anthem, europe-wall, \
    hiatus-return, transition, brent, vince.
    Only link shows whose dates you verified via tools or the provided context. \
    Availability matters: before recommending a specific show, confirm a tape \
    exists with best_recording_for_date. If no recording exists in the archive, \
    say so plainly and suggest a nearby night that IS available instead of \
    linking it. Keep replies conversational, 2-6 sentences unless asked for depth.
    """

    private var chatTools: JSONValue {
        func prop(_ type: String, _ description: String) -> JSONValue {
            .object(["type": .array([.string(type), .string("null")]), "description": .string(description)])
        }
        func tool(_ name: String, _ description: String, _ properties: [String: JSONValue]) -> JSONValue {
            .object([
                "type": .string("function"),
                "name": .string(name),
                "description": .string(description),
                "strict": .bool(true),
                "parameters": .object([
                    "type": .string("object"),
                    "properties": .object(properties),
                    "required": .array(properties.keys.sorted().map(JSONValue.string)),
                    "additionalProperties": .bool(false),
                ]),
            ])
        }
        return .array([
            tool("search_archive",
                 "Search the Internet Archive's Grateful Dead collection for live shows.",
                 [
                    "yearStart": prop("integer", "Earliest year, 1965-1995"),
                    "yearEnd": prop("integer", "Latest year, 1965-1995"),
                    "venueText": prop("string", "Venue or city to match"),
                    "minRating": prop("number", "Minimum community rating 0-5"),
                    "soundboardOnly": prop("boolean", "Only soundboard recordings"),
                 ]),
            tool("lookup_song",
                 "Get a song's history, evolution, famous versions, and segue partners from the curated knowledge base.",
                 ["title": prop("string", "Song title, e.g. 'Dark Star'")]),
            tool("best_recording_for_date",
                 "Find the best archive recording of a specific show date. Use to verify a show exists before linking it.",
                 ["date": prop("string", "Show date as YYYY-MM-DD")]),
        ])
    }

    private func runTool(name: String, argumentsJSON: String) async -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) as? [String: Any] ?? [:]
        switch name {
        case "search_archive":
            var filters = SearchFilters()
            let start = args["yearStart"] as? Int
            let end = args["yearEnd"] as? Int
            if let start { filters.yearRange = start...(max(end ?? start, start)) }
            filters.venueText = args["venueText"] as? String
            filters.minRating = args["minRating"] as? Double
            filters.soundboardOnly = args["soundboardOnly"] as? Bool
            filters.sortByRating = true
            let shows = (try? await archive.search(filters: filters, rows: 30)) ?? []
            let ranked = RecordingRanker.rank(shows).prefix(6)
            if ranked.isEmpty { return "No shows found. Broaden the search." }
            return ranked.map { show in
                "date=\(show.dateString ?? "?") venue=\(show.displayVenue) rating=\(show.avgRating.map { String(format: "%.1f", $0) } ?? "n/a") sbd=\(show.isSoundboard)"
            }.joined(separator: "\n")
        case "lookup_song":
            guard let title = args["title"] as? String,
                  let song = kb.song(matching: title) else {
                return "Song not found in the knowledge base."
            }
            var lines = ["key=\(song.key) title=\(song.title)", song.evolution]
            for famous in song.famousVersions {
                lines.append("famous version date=\(famous.date) label=\(famous.label ?? "") note=\(famous.note)")
            }
            if !song.seguePartners.isEmpty {
                lines.append("segue partners: \(song.seguePartners.joined(separator: ", "))")
            }
            return lines.joined(separator: "\n")
        case "best_recording_for_date":
            guard let date = args["date"] as? String else { return "Missing date." }
            let recordings = (try? await archive.recordings(forDate: date)) ?? []
            guard let best = RecordingRanker.rank(recordings).first else {
                return "No archive recordings found for \(date)."
            }
            var line = "date=\(date) venue=\(best.displayVenue) identifier=\(best.identifier) sources=\(recordings.count)"
            if let rating = best.avgRating { line += String(format: " rating=%.1f", rating) }
            if let notable = kb.notableShow(on: date) { line += " curatorNote=\(notable.blurb)" }
            return line
        default:
            return "Unknown tool."
        }
    }

    func chatReply(messages: [ChatTurn], grounding: GroundingContext) async throws -> AsyncThrowingStream<String, any Error> {
        let apiKey = try requireKey()

        var contextLines: [String] = []
        if let nowPlaying = grounding.nowPlaying { contextLines.append("Now playing: \(nowPlaying)") }
        if !grounding.recentShows.isEmpty { contextLines.append("Recently heard: \(grounding.recentShows.joined(separator: "; "))") }
        if let taste = grounding.tasteSummary { contextLines.append("Taste: \(taste)") }
        if !grounding.knowledgeSnippets.isEmpty {
            contextLines.append("Reference notes:\n" + grounding.knowledgeSnippets.joined(separator: "\n"))
        }

        let transcript = messages.suffix(12).map { "\($0.role == .user ? "Listener" : "You"): \($0.text)" }
            .joined(separator: "\n")
        let prompt = """
        Context:
        \(contextLines.isEmpty ? "none" : contextLines.joined(separator: "\n"))

        Conversation so far:
        \(transcript)

        Reply to the listener's last message.
        """

        // Tool loop: up to 3 rounds of function calls, then a final text answer.
        var body: JSONValue = .object([
            "model": .string(model),
            "instructions": .string(Self.chatInstructions),
            "input": .string(prompt),
            "tools": chatTools,
        ])

        var finalText: String?
        for _ in 0..<4 {
            let data = try await Self.sendRaw(body, apiKey: apiKey)
            let reply = try JSONDecoder().decode(ResponsesReply.self, from: data)
            let calls = reply.functionCalls
            if calls.isEmpty {
                finalText = reply.outputText
                break
            }
            var outputs: [JSONValue] = []
            for call in calls {
                let result = await runTool(name: call.name ?? "", argumentsJSON: call.arguments ?? "{}")
                outputs.append(.object([
                    "type": .string("function_call_output"),
                    "call_id": .string(call.callId ?? ""),
                    "output": .string(String(result.prefix(3000))),
                ]))
            }
            body = .object([
                "model": .string(model),
                "previous_response_id": .string(reply.id ?? ""),
                "input": .array(outputs),
                "tools": chatTools,
            ])
        }

        guard let finalText, !finalText.isEmpty else { throw AIError.badResponse }

        // Yield in small chunks so the UI keeps its streaming feel.
        let chunks = Self.chunked(finalText)
        return AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in chunks {
                    try? await Task.sleep(for: .milliseconds(40))
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated private static func sendRaw(_ body: JSONValue, apiKey: String) async throws -> Data {
        var urlRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 120
        urlRequest.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw AIError.missingKey
        case 429: throw AIError.rateLimited
        default: throw AIError.badResponse
        }
    }

    nonisolated private static func chunked(_ text: String, size: Int = 24) -> [String] {
        var chunks: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            current += (current.isEmpty ? "" : " ") + word
            if current.count >= size {
                chunks.append(current + " ")
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

// MARK: - Composite provider (OpenAI when keyed, local otherwise)

/// Tries OpenAI when a key is present; falls back to the offline brain on any
/// failure so AI features never break.
final class CompositeAIProvider: AIProvider {
    private let local: LocalKnowledgeAI
    private let remote: OpenAIResponsesAI

    init(knowledgeBase: KnowledgeBase) {
        self.local = LocalKnowledgeAI(knowledgeBase: knowledgeBase)
        self.remote = OpenAIResponsesAI(knowledgeBase: knowledgeBase)
    }

    var name: String { KeychainStore.hasUsableKey ? remote.name : local.name }
    var isUsingRemote: Bool { KeychainStore.hasUsableKey }

    func recommend(query: String?, profile: TasteSnapshot, candidates: [Show]) async throws -> Recommendation {
        if KeychainStore.hasUsableKey, let result = try? await remote.recommend(query: query, profile: profile, candidates: candidates) {
            return result
        }
        return try await local.recommend(query: query, profile: profile, candidates: candidates)
    }

    func showGuide(for detail: RecordingDetail, show: Show?) async throws -> ShowGuide {
        if KeychainStore.hasUsableKey, let result = try? await remote.showGuide(for: detail, show: show) {
            return result
        }
        return try await local.showGuide(for: detail, show: show)
    }

    func parseSearchIntent(_ text: String) async throws -> SearchFilters {
        if KeychainStore.hasUsableKey, let result = try? await remote.parseSearchIntent(text) {
            return result
        }
        return try await local.parseSearchIntent(text)
    }

    func curateCollection(brief: CollectionBrief, candidates: [CollectionCandidate]) async throws -> CuratedCollection {
        if KeychainStore.hasUsableKey,
           let result = try? await remote.curateCollection(brief: brief, candidates: candidates) {
            return result
        }
        return try await local.curateCollection(brief: brief, candidates: candidates)
    }

    func chatReply(messages: [ChatTurn], grounding: GroundingContext) async throws -> AsyncThrowingStream<String, any Error> {
        if KeychainStore.hasUsableKey {
            do {
                return try await remote.chatReply(messages: messages, grounding: grounding)
            } catch {
                // fall through to local
            }
        }
        return try await local.chatReply(messages: messages, grounding: grounding)
    }
}

// MARK: - Minimal JSON value (for encoding JSON Schema bodies)

nonisolated indirect enum JSONValue: Encodable, Sendable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
