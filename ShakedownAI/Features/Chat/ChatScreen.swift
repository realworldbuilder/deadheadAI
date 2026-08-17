import SwiftUI
import SwiftData

@Observable
final class ChatModel {
    struct DisplayMessage: Identifiable, Hashable {
        let id: UUID
        var role: ChatTurn.Role
        var text: String
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
                .map { DisplayMessage(id: UUID(), role: $0.role == "user" ? .user : .assistant, text: $0.text) }
        } else {
            let fresh = ChatThread(title: "Deadhead AI")
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
            let stream = try await env.aiProvider.chatReply(messages: Array(turns), grounding: buildGrounding(for: text))
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
            var final = messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
            final = await verifyLinks(in: final)
            messages[index].text = final
            persist(role: "assistant", text: final)
        }
        isReplying = false
    }

    /// Every show link is checked against the archive before it's presented:
    /// confirmed tapes get a ▶ marker, misses become plain text that says so.
    /// Lookups hit the SwiftData cache first, so repeats are free.
    private func verifyLinks(in text: String) async -> String {
        let dates = ChatLink.showDates(in: text).prefix(8)
        guard !dates.isEmpty else { return text }
        var availability: [String: Bool] = [:]
        for date in dates {
            if let recordings = try? await env.recordingProvider.recordings(forDate: date) {
                availability[date] = !recordings.isEmpty
            }
            // A failed lookup (network hiccup) leaves the link untouched
            // rather than wrongly declaring the show missing.
        }
        return ChatLink.verifyShowTokens(text, availability: availability)
    }

    private func persist(role: String, text: String) {
        guard let thread else { return }
        let record = ChatMessageRecord(role: role, text: text)
        record.thread = thread
        context.insert(record)
        try? context.save()
    }

    /// Grounding context: now playing, recent listens, and KB snippets matched
    /// to the question so even the remote model stays anchored in real data.
    private func buildGrounding(for question: String) -> GroundingContext {
        var snippets: [String] = []
        let kb = env.knowledgeBase
        if let song = kb.song(matching: question) ?? LocalKnowledgeAI.songMention(in: question, kb: kb) {
            var line = "\(song.title): \(song.evolution)"
            for famous in song.famousVersions.prefix(3) {
                line += " Famous version \(famous.date): \(famous.note)"
            }
            snippets.append(line)
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
            ZStack {
                SpaceBackground()
                VStack(spacing: 0) {
                    if let model {
                        messagesList(model)
                        inputBar(model)
                    }
                }
            }
            .navigationTitle("Deadhead AI")
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
        .tint(Theme.accent)
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
        ZStack {
            SpaceBackground()
            ErrorCard(message: message, retry: nil)
                .padding(Theme.screenPadding)
        }
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
        }
    }

    private func emptyState(_ model: ChatModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your lifelong Deadhead, riding shotgun.")
                .font(Theme.display(26))
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
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Theme.surfaceRaised))
                .overlay(Capsule().strokeBorder(Theme.stroke))

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(model.draft.isEmpty || model.isReplying ? Theme.textTertiary : Theme.accent)
                }
                .disabled(model.draft.isEmpty || model.isReplying)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 10)
            .background(Theme.background)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatModel.DisplayMessage

    private var renderedText: AttributedString {
        message.role == .assistant
            ? ChatLink.render(message.text.isEmpty ? " " : message.text, linkColor: Theme.rose)
            : AttributedString(message.text.isEmpty ? " " : message.text)
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(renderedText)
                .font(message.role == .user ? Theme.body : .system(.body, design: .serif))
                .foregroundStyle(message.role == .user ? Color.black.opacity(0.85) : Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(message.role == .user
                              ? AnyShapeStyle(Theme.accentGradient)
                              : AnyShapeStyle(Theme.surface))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(message.role == .user ? Color.clear : Theme.stroke)
                )
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
