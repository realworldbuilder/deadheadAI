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
    @State private var motion = SkyMotion()
    @State private var path = NavigationPath()

    private enum Destination: String, Hashable {
        case search, topShelf, eras, songs, journeys, darkStar, onThisDay,
             journal, taste, years
    }

    /// Debug hooks for CLI screenshot capture: `--stage-explore eras` opens
    /// a destination straight from the sky; `--stage-era europe-wall` goes
    /// one deeper, onto that era's page.
    private func stageFromArguments() {
        guard path.isEmpty else { return }
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--stage-explore"), index + 1 < args.count,
           let destination = Destination(rawValue: args[index + 1]) {
            path.append(destination)
        }
        if let index = args.firstIndex(of: "--stage-era"), index + 1 < args.count,
           let era = env.knowledgeBase.era(id: args[index + 1]) {
            if path.isEmpty { path.append(Destination.eras) }
            path.append(era)
        }
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
        var tint: Color = Sky.ink
        /// Rotation of the body's art — only the comet listens, so its tail
        /// can stream away from the sun.
        var heading: Angle = .zero
    }

    private enum LabelSide { case leading, trailing, top, bottom }

    private static let labelWidth: CGFloat = 116
    private static let labelHeight: CGFloat = 40
    private static let labelGap: CGFloat = 10
    private static let amber = Color(red: 1.0, green: 0.86, blue: 0.42)

    /// A ring around the emblem, the way dead.net hung its sections around
    /// the stealie: one body at the top, one at the foot, and four pairs
    /// mirrored left and right at matched heights. Not ruler-straight —
    /// the drift keeps it breathing — but balanced, so the eye reads the
    /// whole sky at once. Sizes run 40–60 so there's still near and far.
    private let stars: [Star] = [
        // Crown
        Star(id: "darkStar", destination: .darkStar, title: "Dark Star",
             style: .galaxy, bodySize: 40, position: UnitPoint(x: 0.50, y: 0.13),
             side: .top, tint: Color(red: 0.64, green: 0.74, blue: 1.0)),
        // First pair: the sun and the ringed planet
        Star(id: "search", destination: .search, title: "Ask the\nArchive",
             style: .sun, bodySize: 58, position: UnitPoint(x: 0.17, y: 0.27),
             side: .trailing, tint: amber),
        Star(id: "eras", destination: .eras, title: "Eras",
             style: .ringed, bodySize: 50, position: UnitPoint(x: 0.83, y: 0.27),
             side: .leading),
        // Second pair, level with the emblem's shoulders
        Star(id: "onThisDay", destination: .onThisDay, title: "On This\nDay",
             style: .moon, bodySize: 40, position: UnitPoint(x: 0.17, y: 0.45),
             side: .bottom),
        Star(id: "taste", destination: .taste, title: "Your\nTaste",
             style: .starburst, bodySize: 40, position: UnitPoint(x: 0.83, y: 0.45),
             side: .bottom),
        // Third pair, level with the wordmark
        Star(id: "years", destination: .years, title: "Years",
             style: .nebula, bodySize: 50, position: UnitPoint(x: 0.16, y: 0.64),
             side: .bottom),
        Star(id: "songs", destination: .songs, title: "Songs",
             style: .spiral, bodySize: 60, position: UnitPoint(x: 0.84, y: 0.64),
             side: .bottom),
        // Fourth pair; the comet's tail streams away from the sun above it.
        Star(id: "journeys", destination: .journeys, title: "Long\nStrange Trip",
             style: .comet, bodySize: 52, position: UnitPoint(x: 0.25, y: 0.79),
             side: .bottom, heading: .degrees(120)),
        Star(id: "journal", destination: .journal, title: "Journal",
             style: .wireGlobe, bodySize: 40, position: UnitPoint(x: 0.75, y: 0.79),
             side: .bottom),
        // Foot
        Star(id: "topShelf", destination: .topShelf, title: "Top Shelf",
             style: .cluster, bodySize: 56, position: UnitPoint(x: 0.50, y: 0.84),
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
        NavigationStack(path: $path) {
            ZStack {
                // Far layer: the field itself barely moves with the phone.
                ZStack {
                    StarfieldBackground()
                    TwinkleLayer()
                        .ignoresSafeArea()
                }
                .scaleEffect(1.05)
                .offset(parallax(depth: 4))
                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    ZStack {
                        ForEach(scenery.indices, id: \.self) { i in
                            let (style, size, point) = scenery[i]
                            PlanetView(style: style, size: size)
                                .opacity(0.75)
                                .modifier(SkyDrift(seed: 100 + i, amplitude: 3))
                                .position(x: point.x * w, y: point.y * h)
                                .offset(parallax(depth: 8))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }

                        emblem
                            .modifier(SkyDrift(seed: 7, amplitude: 2))
                            .position(x: 0.5 * w, y: 0.50 * h)
                            .offset(parallax(depth: 18))

                        ForEach(Array(stars.enumerated()), id: \.element.id) { index, star in
                            NavigationLink(value: star.destination) {
                                starLabel(star)
                            }
                            .buttonStyle(StarButtonStyle(glow: star.tint))
                            .modifier(SkyDrift(seed: index, amplitude: 5))
                            .position(x: star.position.x * w + offset(star).width,
                                      y: star.position.y * h + offset(star).height)
                            .offset(parallax(depth: 12))
                        }
                    }
                    .frame(width: w, height: h)
                }
                .padding(.top, 8)
                .withMiniPlayer()
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await sky.refresh(env: env) }
            .onAppear {
                motion.start()
                Task { await sky.refresh(env: env) }
            }
            .task {
                // A push during the first render is dropped, and the view can
                // be rebuilt once more while the app settles — so try a few
                // times until the path holds.
                for _ in 0..<4 {
                    try? await Task.sleep(for: .seconds(1))
                    stageFromArguments()
                }
            }
            .onDisappear { motion.stop() }
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
                case .years:
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
            .navigationDestination(for: EraInfo.self) { era in
                EraDetailScreen(era: era)
            }
        }
        .tint(Theme.textPrimary)
    }

    /// The centrepiece: the wordmark over the rooted-stealie mark, the way
    /// the old page hung GRATEFUL DEAD over the stealie in the middle of the
    /// solar system, with tonight's moon named beneath. It's the biggest thing on
    /// the map, so it goes somewhere: tonight's show.
    @ViewBuilder
    private var emblem: some View {
        let art = VStack(spacing: 8) {
            Text("TapeTree")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .skyChrome()
            AppMark(size: 124)
                .overlay(Circle().strokeBorder(Sky.accent.opacity(0.35), lineWidth: 1))
                .shadow(color: Sky.accent.opacity(0.45), radius: 28)
            Text(MoonPhase.name(for: sky.moonPhase))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Sky.inkFaint)
        }
        if let hero = sky.hero {
            NavigationLink(value: hero) { art }
                .buttonStyle(StarButtonStyle(glow: Sky.accent))
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
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Sky.inkSoft)
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
        case "years": sky.yearsCaption
        default: nil
        }
    }

    /// Parallax: nearer layers slide further with the phone's tilt.
    private func parallax(depth: CGFloat) -> CGSize {
        CGSize(width: motion.tilt.width * depth, height: motion.tilt.height * depth)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
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
}
