import SwiftUI

@Observable
final class NaturalSearchModel {
    var query = ""
    var results: [Show] = []
    var kbSuggestions: [NotableShow] = []
    var songContext: SongInfo?
    var isSearching = false
    var searched = false
    var errorMessage: String?

    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    static let examplePrompts = [
        "Best China Rider",
        "I'm exhausted",
        "Most psychedelic second set",
        "Primal Dead from 1968",
        "Best audience tapes",
        "Shows for new listeners",
        "I want Phil bombs",
        "Terrifying Dark Star",
        "Something like Cornell",
        "Rainy Sunday morning",
    ]

    func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        searched = true
        errorMessage = nil
        results = []
        songContext = nil

        // Knowledge-base picks always come back instantly, even offline.
        let tags = LocalKnowledgeAI.tags(inQuery: text)
        kbSuggestions = env.knowledgeBase.shows(matchingTags: tags, limit: 6)

        do {
            let filters = try await env.aiProvider.parseSearchIntent(text)

            // A song query is best answered by its famous versions.
            if let songTitle = filters.songText,
               let song = env.knowledgeBase.song(matching: songTitle) {
                songContext = song
                var famous: [Show] = []
                for version in song.famousVersions.prefix(4) {
                    if let best = (try? await env.recordingProvider.recordings(forDate: version.date))?.first {
                        famous.append(best)
                    }
                }
                if !famous.isEmpty {
                    results = famous
                    isSearching = false
                    return
                }
            }

            results = try await env.recordingProvider.shows(matching: filters)
            if results.isEmpty && kbSuggestions.isEmpty {
                errorMessage = "Nothing surfaced for that. Try a mood, a year, a song, or a venue."
            }
        } catch HTTPError.serviceUnavailable {
            if kbSuggestions.isEmpty {
                errorMessage = ArchiveHealth.outageMessage
            }
        } catch {
            if kbSuggestions.isEmpty {
                errorMessage = "The archive didn't answer — but the offline brain still works. Try a mood or era."
            }
        }
        isSearching = false
    }
}

struct NaturalSearchScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: NaturalSearchModel?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchField
                    if let model {
                        if model.isSearching {
                            LoadingLampView(text: "Reading your mind…")
                        } else if model.searched {
                            resultsSection(model)
                        } else {
                            promptIdeas(model)
                        }
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle("Ask the Archive")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if model == nil { model = NaturalSearchModel(env: env) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(Theme.accent)
            TextField("Describe what you want to hear…", text: Binding(
                get: { model?.query ?? "" },
                set: { model?.query = $0 }
            ))
            .font(Theme.body)
            .foregroundStyle(Theme.textPrimary)
            .focused($focused)
            .submitLabel(.search)
            .onSubmit { Task { await model?.search() } }
            if !(model?.query.isEmpty ?? true) {
                Button {
                    model?.query = ""
                    model?.searched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(14)
        .cardStyle(raised: true)
    }

    private func promptIdeas(_ model: NaturalSearchModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No filters. No dates. Just say it.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
            FlowingChips(prompts: NaturalSearchModel.examplePrompts) { prompt in
                model.query = prompt
                Task { await model.search() }
            }
        }
    }

    @ViewBuilder
    private func resultsSection(_ model: NaturalSearchModel) -> some View {
        if let song = model.songContext {
            VStack(alignment: .leading, spacing: 6) {
                Text(song.title).sectionHeaderStyle()
                Text("The versions Deadheads argue about, resolved to the best tapes:")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        if let error = model.errorMessage {
            ErrorCard(message: error, retry: nil)
        }
        ForEach(model.results) { show in
            NavigationLink(value: show) { ShowRow(show: show) }
                .buttonStyle(.plain)
        }
        if !model.kbSuggestions.isEmpty {
            Text("From the Curator's Shelf")
                .sectionHeaderStyle()
                .padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.kbSuggestions) { notable in
                        NavigationLink(value: notable) {
                            NotableShowCard(notable: notable, era: env.knowledgeBase.era(id: notable.eraID))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Wrapping chip layout for example prompts.
struct FlowingChips: View {
    let prompts: [String]
    let action: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(prompts, id: \.self) { prompt in
                Button { action(prompt) } label: {
                    Text(prompt)
                        .font(Theme.mono(12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.surfaceRaised))
                        .overlay(Capsule().strokeBorder(Theme.stroke))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal flow layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.last.map { $0.minY + $0.height } ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: proposal, subviews: subviews)
        var index = 0
        for row in rows {
            var x = bounds.minX
            for size in row.sizes {
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.minY),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
                index += 1
            }
        }
    }

    private struct Row {
        var sizes: [CGSize] = []
        var minY: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        var y: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if current.width + size.width > maxWidth, !current.sizes.isEmpty {
                current.minY = y
                rows.append(current)
                y += current.height + spacing
                current = Row()
            }
            current.sizes.append(size)
            current.width += size.width + spacing
            current.height = max(current.height, size.height)
        }
        if !current.sizes.isEmpty {
            current.minY = y
            rows.append(current)
        }
        return rows
    }
}
