import SwiftUI

// MARK: - Explore tab — the constellation

/// The Explore hub drawn as a celestial image map, in the spirit of the 1996
/// dead.net home page: no cards and no rows, just labelled planets, comets and
/// galaxies scattered across black space around a central emblem. Everything
/// here is our own artwork — the centrepiece is the house spiral, not the
/// band's trademarked skull.
struct ExploreTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var sky = ExploreSkyModel()

    private enum Destination: Hashable {
        case search, topShelf, eras, songs, journeys, darkStar, onThisDay,
             journal, taste, vault
    }

    /// One labelled body in the map. `position` is where the *body* sits in
    /// unit space; the label hangs off the given side without moving it.
    private struct Star: Identifiable {
        let id: String
        let destination: Destination
        let title: String
        let style: PlanetView.Style
        var bodySize: CGFloat = 46
        let position: UnitPoint
        let side: LabelSide
        var tint: Color = Theme.textPrimary
        /// Rotation of the body's art — only the comet listens, so its tail
        /// can stream away from the sun.
        var heading: Angle = .zero
    }

    private enum LabelSide { case leading, trailing, top, bottom }

    private static let labelWidth: CGFloat = 116
    private static let labelHeight: CGFloat = 40
    private static let labelGap: CGFloat = 10
    private static let amber = Color(red: 1.0, green: 0.86, blue: 0.42)

    /// A scatter, not a system. No rings, no mirrored pairs — every body
    /// hangs at its own height and drift, the way stars actually fall across
    /// a sky. Positions are hand-jittered: nothing shares a row or column
    /// with its neighbour, and everything steers clear of the emblem and
    /// wordmark in the middle. Sizes run 40–60 so the sky has near and far.
    private let stars: [Star] = [
        Star(id: "darkStar", destination: .darkStar, title: "Dark Star",
             style: .galaxy, bodySize: 40, position: UnitPoint(x: 0.62, y: 0.10),
             side: .top, tint: Color(red: 0.64, green: 0.74, blue: 1.0)),
        Star(id: "search", destination: .search, title: "Ask the\nArchive",
             style: .sun, bodySize: 58, position: UnitPoint(x: 0.18, y: 0.19),
             side: .trailing, tint: amber),
        Star(id: "eras", destination: .eras, title: "Eras",
             style: .ringed, bodySize: 50, position: UnitPoint(x: 0.83, y: 0.22),
             side: .bottom),
        Star(id: "onThisDay", destination: .onThisDay, title: "On This\nDay",
             style: .moon, bodySize: 40, position: UnitPoint(x: 0.17, y: 0.38),
             side: .bottom),
        Star(id: "taste", destination: .taste, title: "Your\nTaste",
             style: .starburst, bodySize: 40, position: UnitPoint(x: 0.84, y: 0.45),
             side: .top),
        Star(id: "songs", destination: .songs, title: "Songs",
             style: .spiral, bodySize: 60, position: UnitPoint(x: 0.78, y: 0.60),
             side: .bottom),
        Star(id: "vault", destination: .vault, title: "The\nVault",
             style: .nebula, bodySize: 50, position: UnitPoint(x: 0.10, y: 0.53),
             side: .trailing),
        // The sun sits up at (0.18, 0.19); the comet's tail streams away from it.
        Star(id: "journeys", destination: .journeys, title: "Long\nStrange Trip",
             style: .comet, bodySize: 52, position: UnitPoint(x: 0.21, y: 0.655),
             side: .trailing, heading: .degrees(125)),
        Star(id: "journal", destination: .journal, title: "Journal",
             style: .wireGlobe, bodySize: 40, position: UnitPoint(x: 0.42, y: 0.74),
             side: .bottom),
        Star(id: "topShelf", destination: .topShelf, title: "Top Shelf",
             style: .cluster, bodySize: 56, position: UnitPoint(x: 0.68, y: 0.82),
             side: .bottom, tint: amber),
    ]

    /// Scenery, kept to a minimum: four faint red giants in the corners.
    /// Everything else in the sky is a real destination.
    private let scenery: [(PlanetView.Style, CGFloat, UnitPoint)] = [
        (.redGiant, 26, UnitPoint(x: 0.13, y: 0.05)),
        (.redGiant, 18, UnitPoint(x: 0.89, y: 0.05)),
        (.redGiant, 20, UnitPoint(x: 0.08, y: 0.94)),
        (.redGiant, 24, UnitPoint(x: 0.92, y: 0.94)),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackground()
                TwinkleLayer()
                    .ignoresSafeArea()
                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    ZStack {
                        ForEach(scenery.indices, id: \.self) { i in
                            let (style, size, point) = scenery[i]
                            PlanetView(style: style, size: size)
                                .opacity(0.75)
                                .position(x: point.x * w, y: point.y * h)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }

                        emblem
                            .position(x: 0.5 * w, y: 0.50 * h)

                        ForEach(stars) { star in
                            NavigationLink(value: star.destination) {
                                starLabel(star)
                            }
                            .buttonStyle(StarButtonStyle(glow: star.tint))
                            .position(x: star.position.x * w + offset(star).width,
                                      y: star.position.y * h + offset(star).height)
                        }
                    }
                    .frame(width: w, height: h)
                }
                .padding(.top, 8)
                .withMiniPlayer()
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await sky.refresh(env: env) }
            .onAppear { Task { await sky.refresh(env: env) } }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await sky.refresh(env: env) }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .search: NaturalSearchScreen()
                case .eras: EraExplorerScreen()
                case .songs: SongExplorerScreen()
                case .journeys: JourneysScreen()
                case .topShelf:
                    ShowListScreen(
                        title: "Top Shelf",
                        subtitle: "The community's highest-rated tapes across three decades.",
                        loader: { try await env.recordingProvider.topRated(yearRange: nil, limit: 40) }
                    )
                case .onThisDay:
                    ShowListScreen(
                        title: "On This Day",
                        subtitle: "Every year the band played this date, best tape of each night first.",
                        loader: { try await env.recordingProvider.onThisDay(monthDay: HomeModel.monthDayString(.now)) }
                    )
                case .darkStar:
                    DarkStarScreen()
                case .vault:
                    BrowseScreen()
                case .journal:
                    JournalListScreen()
                case .taste:
                    TasteProfileScreen()
                }
            }
            .navigationDestination(for: Show.self) { show in
                ShowDetailScreen(show: show)
            }
            .navigationDestination(for: NotableShow.self) { notable in
                NotableShowResolverScreen(notable: notable)
            }
        }
        .tint(Theme.accent)
    }

    /// The centrepiece: our spiral over the wordmark, the way the old page
    /// hung its logo in the middle of the solar system. It's the biggest
    /// thing on the map, so it goes somewhere: tonight's show.
    @ViewBuilder
    private var emblem: some View {
        let art = VStack(spacing: 6) {
            SpiralMandala(size: 116)
                .shadow(color: Theme.denim.opacity(0.5), radius: 26)
            Text("TapeTree")
                .font(Theme.display(21))
                .chromeText()
        }
        if let hero = sky.hero {
            NavigationLink(value: hero) { art }
                .buttonStyle(StarButtonStyle(glow: Theme.denim))
                .accessibilityLabel("Tonight's show")
        } else {
            art.allowsHitTesting(false)
        }
    }

    /// A body with its label alongside. The body stays on its unit point; the
    /// group is shifted by exactly half the label's extent to keep it there.
    private func starLabel(_ star: Star) -> some View {
        let text = Text(star.title)
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(star.tint)
            .shadow(color: .black, radius: 3)
            .shadow(color: star.tint.opacity(0.45), radius: 8)
            .lineSpacing(1)
        let body = PlanetView(style: star.style, size: star.bodySize,
                              moonPhase: sky.moonPhase, heading: star.heading)

        return Group {
            switch star.side {
            case .trailing:
                HStack(spacing: Self.labelGap) {
                    body
                    text.frame(width: Self.labelWidth, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
            case .leading:
                HStack(spacing: Self.labelGap) {
                    text.frame(width: Self.labelWidth, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                    body
                }
            case .bottom:
                VStack(spacing: Self.labelGap) {
                    body
                    text.frame(width: Self.labelWidth, height: Self.labelHeight, alignment: .top)
                        .multilineTextAlignment(.center)
                        .overlay(alignment: .top) { caption(for: star) }
                }
            case .top:
                VStack(spacing: Self.labelGap) {
                    text.frame(width: Self.labelWidth, height: Self.labelHeight, alignment: .bottom)
                        .multilineTextAlignment(.center)
                    body
                }
            }
        }
        .contentShape(Rectangle())
    }

    /// The live line under a label — "Sep 1 · 12 shows", "3 entries". Drawn
    /// as an overlay so it takes no layout space and the body-anchoring math
    /// in `offset(_:)` stays exact.
    @ViewBuilder
    private func caption(for star: Star) -> some View {
        if let line = captionText(for: star) {
            let lines = CGFloat(star.title.split(separator: "\n").count)
            Text(line)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textSecondary)
                .shadow(color: .black, radius: 3)
                .lineLimit(1)
                .fixedSize()
                .offset(y: lines * 19 + 2)
        }
    }

    private func captionText(for star: Star) -> String? {
        switch star.id {
        case "onThisDay": sky.onThisDayCaption
        case "journal": sky.journalCaption
        default: nil
        }
    }

    private func offset(_ star: Star) -> CGSize {
        let dx = (Self.labelGap + Self.labelWidth) / 2
        let dy = (Self.labelGap + Self.labelHeight) / 2
        switch star.side {
        case .trailing: return CGSize(width: dx, height: 0)
        case .leading: return CGSize(width: -dx, height: 0)
        case .bottom: return CGSize(width: 0, height: dy)
        case .top: return CGSize(width: 0, height: -dy)
        }
    }
}

// MARK: - Dark Star

/// The mystery destination: one great tape, chosen by the void. Draws from
/// the community's top shelf so the surprise is never a dud.
struct DarkStarScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var show: Show?
    @State private var failed = false

    var body: some View {
        ZStack {
            SpaceBackground()
            if let show {
                ShowDetailScreen(show: show)
            } else if failed {
                ErrorCard(message: ArchiveHealth.shared.isOffline
                          ? ArchiveHealth.outageMessage
                          : "The Dark Star wouldn't resolve. Give it another spin.") {
                    failed = false
                    Task { await resolve() }
                }
                .padding(Theme.screenPadding)
            } else {
                LoadingLampView(text: "Following the Dark Star…")
            }
        }
        .task { await resolve() }
    }

    private func resolve() async {
        guard show == nil else { return }
        let candidates = (try? await env.recordingProvider.topRated(yearRange: nil, limit: 60)) ?? []
        show = candidates.randomElement()
        failed = show == nil
    }
}

#Preview {
    ExploreTabView()
        .environment(AppEnvironment.mock())
        .preferredColorScheme(.dark)
}
