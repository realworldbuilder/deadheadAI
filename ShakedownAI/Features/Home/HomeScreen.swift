import SwiftUI

@Observable
final class HomeModel {
    var hero: NotableShow?
    var heroRecording: Show?
    var heroNarrative: Recommendation?
    var becauseYouLiked: [NotableShow] = []
    var onThisDay: [Show] = []
    var recentShows: [(identifier: String, displayName: String, lastPlayed: Date)] = []
    var quote: BandQuote?
    var isLoadingHero = false

    private let env: AppEnvironment
    private var loadedForDay: Int?

    init(env: AppEnvironment) {
        self.env = env
    }

    func load() async {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 1
        refreshLocalSections(dayOfYear: dayOfYear)
        guard loadedForDay != dayOfYear else { return }
        loadedForDay = dayOfYear

        isLoadingHero = true
        defer { isLoadingHero = false }

        // Resolve the hero pick to a real archive recording.
        if let hero {
            heroRecording = (try? await env.recordingProvider.recordings(forDate: hero.date))?.first
        }

        // On This Day: real archive lookup, cached hard by the provider.
        let monthDay = Self.monthDayString(.now)
        onThisDay = (try? await env.recordingProvider.onThisDay(monthDay: monthDay)) ?? []
    }

    func refreshLocalSections(dayOfYear: Int) {
        let taste = env.history.tasteSnapshot
        hero = env.knowledgeBase.heroShow(dayOfYear: dayOfYear, taste: taste)
        quote = env.knowledgeBase.quote(dayOfYear: dayOfYear)
        recentShows = env.history.recentShows(limit: 8)
        becauseYouLiked = env.knowledgeBase.recommendations(
            for: taste,
            excluding: hero.map { [$0.date] } ?? [],
            limit: 6
        )
    }

    func loadHeroNarrative() async {
        guard heroNarrative == nil, let heroRecording else { return }
        heroNarrative = try? await env.aiProvider.recommend(
            query: nil,
            profile: env.history.tasteSnapshot,
            candidates: [heroRecording]
        )
    }

    nonisolated static func monthDayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }
}

struct HomeScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(PlayerEngine.self) private var engine
    @State private var model: HomeModel?
    @State private var showingWhy = false

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        if let model {
                            if let hero = model.hero {
                                HeroCard(
                                    notable: hero,
                                    recording: model.heroRecording,
                                    isLoading: model.isLoadingHero,
                                    onWhy: {
                                        showingWhy = true
                                        Task { await model.loadHeroNarrative() }
                                    }
                                )
                            }
                            SmartShelfStrip()
                            if !model.becauseYouLiked.isEmpty {
                                notableShelf(
                                    title: model.recentShows.isEmpty ? "Start Here" : "Because You've Been Listening",
                                    shows: model.becauseYouLiked
                                )
                            }
                            if !model.onThisDay.isEmpty {
                                onThisDaySection(model.onThisDay)
                            }
                            if !model.recentShows.isEmpty {
                                recentSection(model.recentShows)
                            }
                            if let quote = model.quote {
                                QuoteCard(quote: quote)
                            }
                        }
                    }
                    .padding(Theme.screenPadding)
                }
                .withMiniPlayer()
            }
            .navigationDestination(for: Show.self) { show in
                ShowDetailScreen(show: show)
            }
            .navigationDestination(for: NotableShow.self) { notable in
                NotableShowResolverScreen(notable: notable)
            }
            .navigationDestination(for: SmartCollection.self) { collection in
                SmartCollectionDetailScreen(collection: collection)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.accent)
        .task {
            if model == nil { model = HomeModel(env: env) }
            await model?.load()
        }
        .sheet(isPresented: $showingWhy) {
            WhySheet(model: model)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Date.now.formatted(date: .complete, time: .omitted).uppercased())
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                Text("DEADHEADS.AI")
                    .font(Theme.display(32))
                    .kerning(1.5)
                    .chromeText()
                Spacer()
                SpiralMandala(size: 40)
            }
            Text("the deadhead's ai companion")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.top, 8)
    }

    private func notableShelf(title: String, shows: [NotableShow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionHeaderStyle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shows) { notable in
                        NavigationLink(value: notable) {
                            NotableShowCard(notable: notable, era: env.knowledgeBase.era(id: notable.eraID))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func onThisDaySection(_ shows: [Show]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(Theme.accent)
                Text("On This Day").sectionHeaderStyle()
            }
            Text("The Dead played \(shows.count) documented show\(shows.count == 1 ? "" : "s") on \(Date.now.formatted(.dateTime.month(.wide).day())).")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            ForEach(shows.prefix(4)) { show in
                NavigationLink(value: show) { ShowRow(show: show) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func recentSection(_ recents: [(identifier: String, displayName: String, lastPlayed: Date)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently Played").sectionHeaderStyle()
            ForEach(recents, id: \.identifier) { recent in
                NavigationLink(value: Show(identifier: recent.identifier, title: recent.displayName,
                                           date: nil, dateString: nil, venue: recent.displayName,
                                           location: nil, year: nil, avgRating: nil,
                                           numReviews: nil, downloads: nil, source: nil)) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.textTertiary)
                        Text(recent.displayName)
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(recent.lastPlayed.formatted(.relative(presentation: .named)))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(12)
                    .cardStyle()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Hero card

private struct HeroCard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(PlayerEngine.self) private var engine

    let notable: NotableShow
    let recording: Show?
    let isLoading: Bool
    let onWhy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TONIGHT'S SHOW")
                .font(Theme.mono(11, weight: .bold))
                .foregroundStyle(Theme.accent)
                .tracking(2)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalKnowledgeAI.prettyDate(notable.date))
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(notable.venue) · \(notable.location)")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(notable.blurb)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(4)

            HStack(spacing: 6) {
                ForEach(notable.tags.prefix(3), id: \.self) { TagPill(text: $0) }
            }

            HStack(spacing: 10) {
                Button {
                    playHero()
                } label: {
                    HStack {
                        if isLoading && recording == nil {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text("Play")
                            .font(Theme.mono(14, weight: .bold))
                    }
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.accentGradient))
                }
                .disabled(recording == nil)

                Button(action: onWhy) {
                    Text("Why?")
                        .font(Theme.mono(14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().strokeBorder(Theme.accent.opacity(0.5)))
                }

                if let recording {
                    NavigationLink(value: recording) {
                        Text("Read")
                            .font(Theme.mono(14, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background(Capsule().strokeBorder(Theme.stroke))
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Theme.heroGradient)
                // A window onto space: the starfield behind shows through the
                // translucent hull, with a nebula glow caught in the corner.
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .fill(Theme.nebulaGradient)
                        .blendMode(.plusLighter)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Theme.accent.opacity(0.45), Theme.stroke.opacity(0.3)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                )
        )
    }

    private func playHero() {
        guard let recording else { return }
        Task {
            if let detail = try? await env.metadataProvider.detail(for: recording.identifier) {
                env.playerEngine.play(show: recording, tracks: detail.tracks)
                env.playerEngine.isPresentingFullPlayer = true
            }
        }
    }
}

// MARK: - Notable show card (horizontal shelf)

struct NotableShowCard: View {
    let notable: NotableShow
    let era: EraInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalKnowledgeAI.prettyDate(notable.date))
                .font(Theme.mono(18, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(notable.venue)
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2, reservesSpace: true)
            Text(notable.location)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let era {
                TagPill(text: era.name, tint: Theme.rose)
            }
        }
        .padding(14)
        .frame(width: 190, height: 150, alignment: .leading)
        .cardStyle(raised: true)
    }
}

// MARK: - Quote

private struct QuoteCard: View {
    let quote: BandQuote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "quote.opening")
                .foregroundStyle(Theme.accent)
            Text(quote.text)
                .font(.system(.title3, design: .serif).italic())
                .foregroundStyle(Theme.textPrimary)
            Text("— \(quote.attribution)")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - Why sheet

private struct WhySheet: View {
    let model: HomeModel?

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Why this show?")
                        .font(Theme.display(28))
                        .foregroundStyle(Theme.textPrimary)
                    if let rec = model?.heroNarrative {
                        Text(rec.narrative)
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                        if !rec.listenFor.isEmpty {
                            Text("Listen for")
                                .font(Theme.title)
                                .foregroundStyle(Theme.textPrimary)
                            ForEach(rec.listenFor, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "waveform")
                                        .foregroundStyle(Theme.accent)
                                        .font(.caption)
                                        .padding(.top, 3)
                                    Text(item)
                                        .font(Theme.body)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    } else {
                        LoadingLampView(text: "Thinking it over…")
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Notable -> archive resolution

/// Resolves a knowledge-base show (a date) to its best archive recording.
struct NotableShowResolverScreen: View {
    @Environment(AppEnvironment.self) private var env
    let notable: NotableShow
    @State private var resolved: Show?
    @State private var failed = false

    var body: some View {
        ZStack {
            SpaceBackground()
            if let resolved {
                ShowDetailScreen(show: resolved)
            } else if failed {
                ErrorCard(message: "Couldn't find this one in the archive right now.") {
                    failed = false
                    Task { await resolve() }
                }
                .padding(Theme.screenPadding)
            } else {
                LoadingLampView(text: "Finding the best tape…")
            }
        }
        .task { await resolve() }
    }

    private func resolve() async {
        let recordings = (try? await env.recordingProvider.recordings(forDate: notable.date)) ?? []
        if let best = recordings.first {
            resolved = best
        } else {
            failed = true
        }
    }
}
