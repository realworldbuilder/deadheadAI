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
    /// Instant offline FTS hits from the bundled catalog ("5-8-77",
    /// "barton hall", "scarlet fire 77") — rendered as-you-type.
    var directHits: [Show] = []

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

    /// Debounced as-you-type lookup against the local catalog.
    func updateDirectHits() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard env.catalog.isAvailable, text.count >= 2 else {
            directHits = []
            return
        }
        directHits = await env.catalog.searchText(text, limit: 8).compactMap(\.asShow)
    }

    /// A query naming a date, year, venue, or song is answered exactly by
    /// the catalog — no AI parse, no network. Mood queries fall through.
    private func looksStructural(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .decimalDigits) != nil
    }

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

        if env.catalog.isAvailable, looksStructural(text) {
            let hits = await env.catalog.searchText(text, limit: 40).compactMap(\.asShow)
            if !hits.isEmpty {
                results = hits
                directHits = []
                isSearching = false
                return
            }
        }
        await updateDirectHits()

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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchField
                if let model {
                    if model.isSearching {
                        LoadingLampView(text: "Reading your mind…")
                    } else if model.searched {
                        resultsSection(model)
                    } else {
                        if !model.directHits.isEmpty {
                            directHitsSection(model)
                        }
                        promptIdeas(model)
                    }
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .withMiniPlayer()
        .navigationTitle("Ask the Archive")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if model == nil { model = NaturalSearchModel(env: env) }
        }
        .task(id: model?.query ?? "") {
            // Debounce the as-you-type catalog lookup.
            guard let model, !model.searched else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await model.updateDirectHits()
        }
    }

    private func directHitsSection(_ model: NaturalSearchModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Direct Hits").sectionHeaderStyle()
            VStack(spacing: 0) {
                ForEach(Array(model.directHits.enumerated()), id: \.element.id) { index, show in
                    NavigationLink(value: show) {
                        ShowRow(show: show, divider: index < model.directHits.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
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
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .cardStyle()
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
        let resultIDs = Set(model.results.map(\.identifier))
        let extraHits = model.directHits.filter { !resultIDs.contains($0.identifier) }
        if !extraHits.isEmpty {
            directHitsSection(model)
        }
        VStack(spacing: 0) {
            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, show in
                NavigationLink(value: show) {
                    ShowRow(show: show, divider: index < model.results.count - 1)
                }
                .buttonStyle(.plain)
            }
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
                Button(prompt) { action(prompt) }
                    .buttonStyle(.chip)
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
