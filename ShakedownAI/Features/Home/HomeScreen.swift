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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
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
                                icon: "star"
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
            .background(Theme.background)
            .withMiniPlayer()
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
        .tint(Theme.textPrimary)
        .task {
            if model == nil { model = HomeModel(env: env) }
            await model?.load()
        }
        .sheet(isPresented: $showingWhy) {
            WhySheet(model: model)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AppMark(size: 28)
                Text("TapeTree")
                    .font(Theme.title)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 14)
    }

    private func notableShelf(title: String, shows: [NotableShow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionHeaderStyle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(shows) { notable in
                        NavigationLink(value: notable) {
                            NotableShowCard(notable: notable, era: env.knowledgeBase.era(id: notable.eraID))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func recentSection(_ recents: [(identifier: String, displayName: String, lastPlayed: Date)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recently Played").sectionHeaderStyle()
            VStack(spacing: 0) {
                ForEach(Array(recents.enumerated()), id: \.element.identifier) { index, recent in
                    NavigationLink(value: Show(identifier: recent.identifier, title: recent.displayName,
                                               date: nil, dateString: nil, venue: recent.displayName,
                                               location: nil, year: nil, avgRating: nil,
                                               numReviews: nil, downloads: nil, source: nil)) {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(Theme.textSecondary)
                            Text(recent.displayName)
                                .font(Theme.body)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(recent.lastPlayed.formatted(.relative(presentation: .named)))
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .listRowStyle(divider: index < recents.count - 1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
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

    /// The night's poster or ticket scan, full-bleed across the card's top.
    /// Only a real scan earns the space; without one the card is just words.
    @ViewBuilder
    private var artworkBanner: some View {
        if let coverImage {
            Color.clear
                .frame(height: 220)
                .overlay(
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                )
                .clipped()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artworkBanner

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tonight's show").eyebrowStyle()
                    Text(LocalKnowledgeAI.prettyDate(notable.date))
                        .font(Theme.title)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(notable.venue) · \(notable.location)")
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }

                Text(notable.blurb)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)

                HStack(spacing: 6) {
                    ForEach(notable.tags.prefix(3), id: \.self) { TagPill(text: $0) }
                }

                HStack(spacing: 8) {
                    Button(action: onPlay) {
                        HStack(spacing: 6) {
                            if isStarting || (isLoading && recording == nil) {
                                ProgressView().tint(Theme.onAccent)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text("Play")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(recording == nil || isStarting)

                    Button("Why?", action: onWhy)
                        .buttonStyle(.secondary)

                    if let recording {
                        NavigationLink(value: recording) {
                            Text("Read")
                        }
                        .buttonStyle(.secondary)
                    }
                }

                if let playError {
                    Text(playError)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.rose)
                }
            }
            .padding(Theme.cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
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
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ArtworkPlaceholder(date: LocalKnowledgeAI.prettyDate(notable.date), venue: notable.venue)
                }
            }
                .frame(width: 190, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
            Text(LocalKnowledgeAI.prettyDate(notable.date))
                .font(Theme.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(notable.venue)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Text(era.map { "\($0.name) · \(notable.location)" } ?? notable.location)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(width: 190, alignment: .leading)
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
            HairlineDivider()
            Text(quote.text)
                .font(Theme.title)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 8)
            Text("— \(quote.attribution)")
                .font(Theme.footnote)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 8)
            HairlineDivider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Why sheet

private struct WhySheet: View {
    let model: HomeModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Why this show?")
                    .font(Theme.largeTitle)
                    .foregroundStyle(Theme.textPrimary)
                if let rec = model?.heroNarrative {
                    Text(rec.narrative)
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                    if !rec.listenFor.isEmpty {
                        Text("Listen for")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                        ForEach(rec.listenFor, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "waveform")
                                    .foregroundStyle(Theme.textSecondary)
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
        .background(Theme.background)
        .presentationBackground(Theme.background)
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
        Group {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
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
