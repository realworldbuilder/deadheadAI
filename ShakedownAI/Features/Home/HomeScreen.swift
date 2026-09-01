import SwiftUI

@Observable
final class HomeModel {
    var hero: NotableShow?
    var heroRecording: Show?
    var heroNarrative: Recommendation?
    var isLoadingNarrative = false
    var narrativeError: String?
    var becauseYouLiked: [NotableShow] = []
    var onThisDay: [Show] = []
    var topShelf: [Show] = []
    var recentShows: [(identifier: String, displayName: String, lastPlayed: Date)] = []
    var quote: BandQuote?
    var isLoadingHero = false
    var isStartingHero = false
    var heroPlayError: String?

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
        heroNarrative = nil
        narrativeError = nil

        isLoadingHero = true
        defer { isLoadingHero = false }

        // Resolve the hero pick to a real archive recording.
        if let hero {
            heroRecording = (try? await env.recordingProvider.recordings(forDate: hero.date))?.first
        }

        // Start writing the "Why this show?" story now, alongside the rest of
        // the feed, so the sheet is ready before anyone taps for it. Cached
        // per day + tape, so relaunches never pay for the same story twice.
        if let heroRecording {
            let key = CacheStore.heroNarrativeKey(identifier: heroRecording.identifier)
            if let cached = env.cache.cachedHeroNarrative(key: key) {
                heroNarrative = cached
            } else {
                Task { await loadHeroNarrative() }
            }
        }

        // On This Day: real archive lookup, cached hard by the provider.
        let monthDay = Self.monthDayString(.now)
        onThisDay = (try? await env.recordingProvider.onThisDay(monthDay: monthDay)) ?? []

        // Top Shelf rail: instant from the catalog, rotated daily so the
        // same twelve don't greet every morning.
        let top = (try? await env.recordingProvider.topRated(yearRange: nil, limit: 40)) ?? []
        if !top.isEmpty {
            let offset = dayOfYear % max(top.count, 1)
            topShelf = Array((top[offset...] + top[..<offset]).prefix(12))
        }
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

    func playHero() async {
        guard let heroRecording, !isStartingHero else { return }
        isStartingHero = true
        heroPlayError = nil
        do {
            let detail = try await env.metadataProvider.detail(for: heroRecording.identifier)
            if detail.tracks.isEmpty {
                heroPlayError = "This tape has no streamable tracks — open the show page to pick another source."
            } else {
                env.playerEngine.play(show: heroRecording, tracks: detail.tracks)
                env.playerEngine.isPresentingFullPlayer = true
            }
        } catch HTTPError.serviceUnavailable {
            heroPlayError = ArchiveHealth.outageMessage
        } catch {
            heroPlayError = "Couldn't reach the archive. Check your connection and try again."
        }
        isStartingHero = false
    }

    func loadHeroNarrative() async {
        guard heroNarrative == nil, !isLoadingNarrative else { return }
        guard let heroRecording else {
            if !isLoadingHero {
                narrativeError = "Couldn't find a tape for tonight's show. Check your connection and try again."
            }
            return
        }
        isLoadingNarrative = true
        narrativeError = nil
        defer { isLoadingNarrative = false }
        do {
            let rec = try await env.aiProvider.recommend(
                query: nil,
                profile: env.history.tasteSnapshot,
                candidates: [heroRecording]
            )
            heroNarrative = rec
            env.cache.storeHeroNarrative(
                rec,
                key: CacheStore.heroNarrativeKey(identifier: heroRecording.identifier)
            )
        } catch {
            narrativeError = "Couldn't write tonight's story right now. Try again in a moment."
        }
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
                                    isStarting: model.isStartingHero,
                                    playError: model.heroPlayError,
                                    onPlay: { Task { await model.playHero() } },
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
                                ShowRail(
                                    title: "Today in Dead History",
                                    subtitle: "The Dead played \(model.onThisDay.count) documented show\(model.onThisDay.count == 1 ? "" : "s") on \(Date.now.formatted(.dateTime.month(.wide).day())).",
                                    shows: model.onThisDay,
                                    icon: "calendar"
                                )
                            }
                            if !model.topShelf.isEmpty {
                                ShowRail(
                                    title: "Top Shelf",
                                    subtitle: "The tapes the community rates highest.",
                                    shows: model.topShelf,
                                    icon: "star.fill"
                                )
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
                Text("TAPETREE")
                    .font(Theme.display(32))
                    .kerning(1.5)
                    .chromeText()
                Spacer()
                SpiralMandala(size: 40)
            }
            Text("first generation, straight from the source")
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
    let notable: NotableShow
    let recording: Show?
    let isLoading: Bool
    let isStarting: Bool
    let playError: String?
    let onPlay: () -> Void
    let onWhy: () -> Void

    @State private var coverImage: UIImage?

    /// The night's poster or ticket scan, full-bleed across the card's top,
    /// with the date rising out of a scrim — the show's face leads.
    private var artworkBanner: some View {
        let artwork = coverImage ?? StubArtwork.image(
            for: recording ?? .artworkPlaceholder(date: notable.date, venue: notable.venue,
                                                  location: notable.location),
            layout: .banner)
        return Color.clear
            .frame(height: 230)
            .overlay(
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
            )
            .clipped()
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .clear, location: 0.45),
                        .init(color: .black.opacity(0.88), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            )
            .overlay(alignment: .topLeading) {
                Text("TONIGHT'S SHOW")
                    .font(Theme.mono(11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .tracking(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(12)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalKnowledgeAI.prettyDate(notable.date))
                        .font(Theme.display(34))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
                    Text("\(notable.venue) · \(notable.location)")
                        .font(Theme.headline)
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                        .lineLimit(2)
                }
                .padding(14)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artworkBanner

            VStack(alignment: .leading, spacing: 12) {
            Text(notable.blurb)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)

            HStack(spacing: 6) {
                ForEach(notable.tags.prefix(3), id: \.self) { TagPill(text: $0) }
            }

            HStack(spacing: 10) {
                Button(action: onPlay) {
                    HStack {
                        if isStarting || (isLoading && recording == nil) {
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
                .disabled(recording == nil || isStarting)

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

            if let playError {
                Text(playError)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.rose)
            }
            }
            .padding(16)
        }
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
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Theme.accent.opacity(0.45), Theme.stroke.opacity(0.3)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .task(id: notable.date + "|" + (recording?.identifier ?? "")) {
            coverImage = await ArchiveArtwork.shared.cover(
                date: notable.date, identifier: recording?.identifier, catalog: env.catalog)
        }
    }
}

// MARK: - Notable show card (horizontal shelf)

struct NotableShowCard: View {
    @Environment(AppEnvironment.self) private var env
    let notable: NotableShow
    let era: EraInfo?

    @State private var coverImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(width: 190, height: 120)
                .overlay(
                    Image(uiImage: coverImage ?? StubArtwork.image(
                        for: .artworkPlaceholder(date: notable.date, venue: notable.venue,
                                                 location: notable.location),
                        layout: .wide))
                        .resizable()
                        .scaledToFill()
                )
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    if let era {
                        Text(era.name)
                            .font(Theme.mono(9, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.65)))
                            .padding(6)
                            .lineLimit(1)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalKnowledgeAI.prettyDate(notable.date))
                    .font(Theme.mono(14, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                Text(notable.venue)
                    .font(Theme.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(notable.location)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(width: 190, alignment: .leading)
        }
        .cardStyle(raised: true)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .task(id: notable.date) {
            coverImage = await ArchiveArtwork.shared.cover(
                date: notable.date, identifier: notable.preferredIdentifier, catalog: env.catalog)
        }
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
                    } else if let error = model?.narrativeError {
                        ErrorCard(message: error) {
                            Task { await model?.loadHeroNarrative() }
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
