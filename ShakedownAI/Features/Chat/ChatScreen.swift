import SwiftUI
import SwiftData

@Observable
final class ChatModel {
    struct DisplayMessage: Identifiable, Hashable {
        let id: UUID
        var role: ChatTurn.Role
        var text: String
        /// Tapes the reply recommended, rendered as playable cards beneath it.
        var shows: [Show] = []
    }

    var messages: [DisplayMessage] = []
    var draft = ""
    var isReplying = false

    private let env: AppEnvironment
    private let context: ModelContext
    private var thread: ChatThread?

    init(env: AppEnvironment) {
        self.env = env
        self.context = env.modelContainer.mainContext
        loadThread()
    }

    static let starterQuestions = [
        "What made 1973 special?",
        "Why do people love Veneta?",
        "What's the Wall of Sound?",
        "When should I start with Brent?",
        "Best Morning Dew for a first-timer?",
        "What makes Europe '72 different?",
    ]

    private func loadThread() {
        let descriptor = FetchDescriptor<ChatThread>(sortBy: [SortDescriptor(\.createdAt)])
        if let existing = (try? context.fetch(descriptor))?.first {
            thread = existing
            messages = existing.messages
                .sorted { $0.createdAt < $1.createdAt }
                .map { DisplayMessage(id: UUID(), role: $0.role == "user" ? .user : .assistant, text: $0.text, shows: $0.shows) }
        } else {
            let fresh = ChatThread(title: "TapeTree")
            context.insert(fresh)
            try? context.save()
            thread = fresh
        }
    }

    func clearConversation() {
        if let thread {
            context.delete(thread)
            try? context.save()
        }
        thread = nil
        messages = []
        loadThread()
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isReplying else { return }
        draft = ""
        await ask(text)
    }

    func ask(_ text: String) async {
        messages.append(DisplayMessage(id: UUID(), role: .user, text: text))
        persist(role: "user", text: text)
        isReplying = true

        let replyID = UUID()
        messages.append(DisplayMessage(id: replyID, role: .assistant, text: ""))

        do {
            let turns = messages.dropLast().suffix(16).map { ChatTurn(role: $0.role, text: $0.text) }
            let stream = try await env.aiProvider.chatReply(messages: Array(turns), grounding: await buildGrounding(for: text))
            for try await delta in stream {
                if let index = messages.firstIndex(where: { $0.id == replyID }) {
                    messages[index].text += delta
                }
            }
        } catch {
            if let index = messages.firstIndex(where: { $0.id == replyID }) {
                messages[index].text = "Lost the thread there — even the best tapes have dropouts. Ask me again?"
            }
        }
        if let index = messages.firstIndex(where: { $0.id == replyID }) {
            let raw = messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            let verified = await verifyLinks(in: raw)
            messages[index].text = verified.text
            messages[index].shows = verified.shows
            persist(role: "assistant", text: verified.text, shows: verified.shows)
        }
        isReplying = false
    }

    /// Every show link is checked against the archive before it's presented:
    /// confirmed tapes get a ▶ marker and a playable card, misses become
    /// plain text that says so. Lookups hit the catalog / SwiftData cache
    /// first, so repeats are free.
    private func verifyLinks(in raw: String) async -> ChatLink.ShowVerification {
        let text = ChatLink.normalizingShowDates(raw)
        let dates = ChatLink.showDates(in: text).prefix(8)
        guard !dates.isEmpty else { return ChatLink.ShowVerification(text: text, shows: []) }
        var lookups: [String: [Show]] = [:]
        for date in dates {
            if let recordings = try? await env.recordingProvider.recordings(forDate: date) {
                lookups[date] = recordings
            }
            // A failed lookup (network hiccup) leaves the link untouched
            // rather than wrongly declaring the show missing.
        }
        return ChatLink.verifyShows(in: text, lookups: lookups)
    }

    private func persist(role: String, text: String, shows: [Show] = []) {
        guard let thread else { return }
        let record = ChatMessageRecord(role: role, text: text)
        record.shows = shows
        record.thread = thread
        context.insert(record)
        try? context.save()
    }

    /// Grounding context: now playing, recent listens, and KB snippets matched
    /// to the question so even the remote model stays anchored in real data.
    /// "5/8/77", "1977-05-08", "may 8 1977" → "1977-05-08" for catalog lookups.
    static func mentionedDates(in text: String) -> [String] {
        ChatLink.isoDates(in: text)
    }

    private func buildGrounding(for question: String) async -> GroundingContext {
        var snippets: [String] = []
        let kb = env.knowledgeBase
        if let song = kb.song(matching: question) ?? LocalKnowledgeAI.songMention(in: question, kb: kb) {
            var line = "\(song.title): \(song.evolution)"
            for famous in song.famousVersions.prefix(3) {
                line += " Famous version \(famous.date): \(famous.note)"
            }
            snippets.append(line)
        }

        // The catalog knows every night, not just the curated 67: real
        // setlists, best tapes, and the community's consensus.
        if env.catalog.isAvailable {
            for date in Self.mentionedDates(in: question).prefix(2) {
                guard let night = await env.catalog.show(onDate: date) else { continue }
                var line = "\(date) \(night.venue ?? "?"), \(night.location ?? "?"):"
                line += " \(night.recordingCount) tapes on the archive, best is \(night.bestSourceType.displayName)."
                if let rating = night.avgRating {
                    line += " Community rating \(String(format: "%.1f", rating)) across \(night.totalReviews) reviews."
                }
                if let setlist = await env.catalog.setlist(forDate: date) {
                    let songs = setlist.sets.map { set in
                        "\(set.label): " + set.entries.map(\.songTitle).joined(separator: ", ")
                    }.joined(separator: " | ")
                    line += " Setlist — \(songs)."
                }
                if let digest = await env.catalog.digest(forShow: night.showID) {
                    line += " Fan consensus: \(digest.consensusSummary)"
                }
                snippets.append(line)
            }
        }
        if let years = LocalKnowledgeAI.years(inQuery: question), let era = kb.era(forYear: years.lowerBound) {
            snippets.append("\(era.name) (\(era.years)): \(era.summary) \(era.context)")
        }
        let lower = question.lowercased()
        for show in kb.notableShows where lower.contains(show.venue.lowercased())
            || lower.contains(show.location.lowercased())
            || lower.contains(show.date) {
            snippets.append("\(show.date) \(show.venue), \(show.location): \(show.blurb) Standouts: \(show.standoutSongs.joined(separator: ", "))")
            if snippets.count > 5 { break }
        }

        let taste = env.history.tasteSnapshot
        let tasteSummary = taste.totalSeconds > 0
            ? "Top songs: \(taste.topSongKeys.prefix(4).joined(separator: ", ")). \(taste.showsHeard) shows heard."
            : nil

        var nowPlaying: String?
        if let show = env.playerEngine.currentShow, let track = env.playerEngine.currentTrack {
            nowPlaying = "\(track.title) from \(show.shortName)"
        }

        return GroundingContext(
            nowPlaying: nowPlaying,
            recentShows: env.history.recentShows(limit: 4).map(\.displayName),
            tasteSummary: tasteSummary,
            knowledgeSnippets: snippets
        )
    }
}

struct ChatScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: ChatModel?
    @State private var path = NavigationPath()
    @State private var confirmingClear = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if let model {
                    messagesList(model)
                    inputBar(model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("TapeTree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Menu {
                    Button(role: .destructive) {
                        confirmingClear = true
                    } label: {
                        Label("Clear conversation", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Conversation options")
            }
            .confirmationDialog(
                "Clear this conversation?",
                isPresented: $confirmingClear,
                titleVisibility: .visible
            ) {
                Button("Clear Conversation", role: .destructive) {
                    model?.clearConversation()
                }
            }
            .sensoryFeedback(.warning, trigger: confirmingClear) { !$0 && $1 }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: model?.isReplying ?? false) { !$0 && $1 }
            .navigationDestination(for: ChatLink.Destination.self) { destination in
                chatLinkScreen(for: destination)
            }
            .navigationDestination(for: Show.self) { show in
                ShowDetailScreen(show: show)
            }
            .navigationDestination(for: NotableShow.self) { notable in
                NotableShowResolverScreen(notable: notable)
            }
            .navigationDestination(for: SongInfo.self) { song in
                SongDetailScreen(song: song)
            }
            .navigationDestination(for: EraInfo.self) { era in
                EraDetailScreen(era: era)
            }
        }
        .tint(Theme.textPrimary)
        // Chat link taps route inside the app instead of Safari.
        .environment(\.openURL, OpenURLAction { url in
            if let destination = ChatLink.destination(for: url) {
                path.append(destination)
                return .handled
            }
            return .systemAction
        })
        .onAppear {
            if model == nil {
                model = ChatModel(env: env)
                // Debug hook: `--demo-ask "question"` auto-asks on launch.
                let args = ProcessInfo.processInfo.arguments
                if let index = args.firstIndex(of: "--demo-ask"), index + 1 < args.count,
                   let model {
                    let question = args[index + 1]
                    Task { await model.ask(question) }
                }
            }
        }
    }

    @ViewBuilder
    private func chatLinkScreen(for destination: ChatLink.Destination) -> some View {
        switch destination {
        case .show(let date):
            NotableShowResolverScreen(notable: notableStub(for: date))
        case .song(let key):
            if let song = env.knowledgeBase.song(forKey: key) ?? env.knowledgeBase.song(matching: key) {
                SongDetailScreen(song: song)
            } else {
                missingScreen("That song isn't in the songbook yet.")
            }
        case .era(let id):
            if let era = env.knowledgeBase.era(id: id) {
                EraDetailScreen(era: era)
            } else {
                missingScreen("That era wandered off the map.")
            }
        }
    }

    /// KB entry when we have one; otherwise a stub the resolver can chase down.
    private func notableStub(for date: String) -> NotableShow {
        env.knowledgeBase.notableShow(on: date) ?? NotableShow(
            date: date,
            venue: "The night of \(LocalKnowledgeAI.prettyDate(date))",
            location: "",
            eraID: TasteEngine.eraID(forYear: Int(date.prefix(4)) ?? 1970),
            tags: [], blurb: "", standoutSongs: [], preferredIdentifier: nil
        )
    }

    private func missingScreen(_ message: String) -> some View {
        ErrorCard(message: message, retry: nil)
            .padding(Theme.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }

    private func messagesList(_ model: ChatModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty {
                        emptyState(model)
                    }
                    ForEach(model.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if model.isReplying && (model.messages.last?.text.isEmpty ?? false) {
                        LoadingLampView(text: "Pulling a tape off the shelf…")
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(Theme.screenPadding)
            }
            .onChange(of: model.messages.last?.text) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            // Cards attach after the final text lands (often unchanged), so
            // they need their own nudge to keep the reply in view.
            .onChange(of: model.messages.last?.shows.count) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func emptyState(_ model: ChatModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your lifelong Deadhead, riding shotgun.")
                .font(Theme.largeTitle)
                .foregroundStyle(Theme.textPrimary)
            Text("I've heard every tape and read every review. Ask me anything — or tell me how tonight feels.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
            FlowingChips(prompts: ChatModel.starterQuestions) { prompt in
                Task { await model.ask(prompt) }
            }
        }
        .padding(.top, 30)
    }

    private func inputBar(_ model: ChatModel) -> some View {
        VStack(spacing: 0) {
            MiniPlayerBar()
                .padding(.bottom, 6)
            HStack(spacing: 10) {
                TextField("Ask, or describe tonight's mood…", text: Binding(
                    get: { model.draft },
                    set: { model.draft = $0 }
                ), axis: .vertical)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { Task { await model.send() } }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.background)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(model.draft.isEmpty || model.isReplying ? Theme.textTertiary : Theme.textPrimary))
                }
                .disabled(model.draft.isEmpty || model.isReplying)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 10)
            .background(Theme.background)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatModel.DisplayMessage

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 56)
                Text(message.text.isEmpty ? " " : message.text)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surfaceRaised))
            }
        } else {
            // Cards sit inline where the reply names each show; prose runs
            // between them keep their song/era links.
            let showsByDate = Dictionary(message.shows.compactMap { show in
                show.dateString.map { ($0, show) }
            }, uniquingKeysWith: { first, _ in first })
            let segments = ChatLink.segments(in: message.text.isEmpty ? " " : message.text,
                                             cardDates: Set(showsByDate.keys))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let text):
                        Text(ChatLink.render(text, linkColor: Theme.accent))
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .show(let date, let note):
                        if let show = showsByDate[date] {
                            ChatShowCard(show: show, note: note)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
