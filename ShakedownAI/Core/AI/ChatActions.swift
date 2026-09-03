import Foundation

/// Something tappable the chat offers beneath a reply: open an era or song
/// page, or feed a follow-up question straight back into the conversation.
nonisolated enum ChatAction: Hashable, Codable, Sendable {
    case openEra(id: String, label: String)
    case openSong(key: String, label: String)
    case ask(String)

    var title: String {
        switch self {
        case .openEra(_, let label): "Explore \(label)"
        case .openSong(_, let label): "Open \(label)"
        case .ask(let question): question
        }
    }

    var systemImage: String {
        switch self {
        case .openEra: "map"
        case .openSong: "music.note"
        case .ask: "bubble.left"
        }
    }
}

/// What the app adds when a reply gave the listener nothing to tap: a
/// couple of tapes to start with (resolved to cards by the chat model) and
/// a row of actions. Deterministic and grounded in the knowledge base, so
/// every tier — including the offline brain — always leads somewhere.
nonisolated struct ChatFollowUp: Equatable, Sendable {
    var showDates: [String] = []
    var actions: [ChatAction] = []
}

nonisolated enum ChatFollowUpPlanner {

    static func plan(question: String, reply: String, kb: KnowledgeBase, showLimit: Int = 2) -> ChatFollowUp {
        var followUp = ChatFollowUp()
        let combined = question + " " + reply
        let lower = combined.lowercased()

        // Era: an explicit year or shorthand ('72) wins, then an era named
        // outright. The question is read first so the listener's own words
        // steer the answer, then the reply.
        let years = LocalKnowledgeAI.years(inQuery: question) ?? LocalKnowledgeAI.years(inQuery: reply)
        let era = years.flatMap { kb.era(forYear: $0.lowerBound) }
            ?? kb.eras.first { lower.contains($0.name.lowercased()) || lower.contains(" \($0.id) ") }

        // Song: the one asked about, else the first one the reply named.
        let song = kb.song(matching: question)
            ?? LocalKnowledgeAI.songMention(in: question, kb: kb)
            ?? LocalKnowledgeAI.songMention(in: reply, kb: kb)

        if let era {
            // Curated nights inside the years actually mentioned, falling
            // back to the era's beginner picks.
            let inEra = kb.shows(inEra: era.id)
            let inYears = years.map { range in inEra.filter { show in range.contains(Int(show.date.prefix(4)) ?? 0) } } ?? []
            let picks = (inYears.isEmpty ? inEra.filter { era.beginnerShows.contains($0.date) } : inYears)
            let dates = (picks.isEmpty ? era.beginnerShows : picks.map(\.date))
            followUp.showDates = Array(dates.prefix(showLimit))
            followUp.actions.append(.openEra(id: era.id, label: era.name))
        } else if let song, let first = song.famousVersions.first {
            followUp.showDates = [first.date]
        }

        if let song {
            followUp.actions.append(.openSong(key: song.key, label: song.title))
        }

        var asks: [String] = []
        if let era {
            let span = years.map { $0.lowerBound == $0.upperBound ? "\($0.lowerBound)" : "\($0.lowerBound)–\($0.upperBound)" } ?? era.years
            asks.append("What's the one show to hear from \(span)?")
        }
        if let song {
            asks.append("Best \(song.title) for a first-timer?")
        }
        if asks.count < 2 {
            asks.append("Pick one show for tonight")
        }
        followUp.actions += asks.prefix(2).map(ChatAction.ask)
        return followUp
    }
}
