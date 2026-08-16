import OSLog
import SwiftUI

enum AppTab: String {
    case home, explore, chat, library, settings
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showingOnboarding = false
    @State private var selectedTab: AppTab = {
        // Debug hook: `--tab explore` opens on a given tab (used by CLI verification).
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--tab"), index + 1 < args.count,
           let tab = AppTab(rawValue: args[index + 1]) {
            return tab
        }
        return .home
    }()

    var body: some View {
        @Bindable var engine = env.playerEngine

        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeScreen()
            }
            Tab("Explore", systemImage: "map.fill", value: .explore) {
                ExploreTabView()
            }
            Tab("Deadhead AI", systemImage: "bubble.left.and.text.bubble.right.fill", value: .chat) {
                ChatScreen()
            }
            Tab("Library", systemImage: "books.vertical.fill", value: .library) {
                LibraryScreen()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                SettingsScreen()
            }
        }
        .background(Theme.background)
        .overlay(alignment: .top) { ArchiveOfflineBanner() }
        .environment(env.playerEngine)
        .sheet(isPresented: $engine.isPresentingFullPlayer) {
            PlayerScreen()
                .environment(env.playerEngine)
                .presentationDragIndicator(.hidden)
        }
        .onAppear {
            if !didOnboard { showingOnboarding = true }
        }
        .sheet(isPresented: $showingOnboarding, onDismiss: { didOnboard = true }) {
            OnboardingSheet()
        }
        .task { await runDemoAutoplayIfRequested() }
    }

    /// Debug hook: `--demo-autoplay` streams the best Cornell '77 source on
    /// launch and logs player state, so streaming is verifiable from the CLI
    /// via `log show --predicate 'subsystem == "ai.deadheads"'`.
    private func runDemoAutoplayIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--demo-autoplay") else { return }
        let log = Logger(subsystem: "ai.deadheads", category: "demo")
        do {
            let shows = try await env.recordingProvider.recordings(forDate: "1977-05-08")
            guard let best = shows.first else {
                log.error("DEMO: no recordings found")
                return
            }
            let detail = try await env.metadataProvider.detail(for: best.identifier)
            log.notice("DEMO: playing \(best.identifier, privacy: .public) tracks=\(detail.tracks.count)")
            env.playerEngine.play(show: best, tracks: detail.tracks)
            for _ in 0..<20 {
                try await Task.sleep(for: .seconds(1))
                let engine = env.playerEngine
                let stateText = String(describing: engine.state)
                let trackText = engine.currentTrack?.title ?? "-"
                log.notice("DEMO: state=\(stateText, privacy: .public) track=\(trackText, privacy: .public) elapsed=\(engine.elapsed, format: .fixed(precision: 1))")
                if case .failed = engine.state { break }
            }
        } catch {
            log.error("DEMO: error \(String(describing: error), privacy: .public)")
        }
    }
}

// MARK: - Explore tab — the constellation

/// The Explore hub drawn as a celestial image map, in the spirit of the 1996
/// dead.net home page: no cards and no rows, just labelled planets, comets and
/// galaxies scattered across black space around a central emblem. Everything
/// here is our own artwork — the centrepiece is the house spiral, not the
/// band's trademarked skull.
struct ExploreTabView: View {
    @Environment(AppEnvironment.self) private var env

    private enum Destination: Hashable {
        case search, topShelf, eras, songs, journeys
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
    }

    private enum LabelSide { case leading, trailing, top, bottom }

    private static let labelWidth: CGFloat = 116
    private static let labelHeight: CGFloat = 40
    private static let labelGap: CGFloat = 10

    /// The system, laid out like a diagram of our own: the emblem is the sun,
    /// three nested orbits ring it, and the destinations sit on the rings in
    /// mirrored pairs — top pair, middle pair, and one world alone at the
    /// bottom. Orbit fractions are of width (rx) and height (ry); each planet
    /// sits exactly on its ring.
    private let orbits: [(rx: CGFloat, ry: CGFloat)] = [
        (0.22, 0.32),   // inner — Top Shelf, at its foot
        (0.28, 0.37),   // middle — the mid pair rides its waist
        (0.34, 0.44),   // outer — the top pair
    ]

    private let stars: [Star] = [
        // Outer orbit, mirrored across the meridian.
        Star(id: "search", destination: .search, title: "Ask the\nArchive",
             style: .sun, bodySize: 50, position: UnitPoint(x: 0.28, y: 0.16),
             side: .trailing, tint: Color(red: 1.0, green: 0.86, blue: 0.42)),
        Star(id: "eras", destination: .eras, title: "Eras",
             style: .ringed, bodySize: 52, position: UnitPoint(x: 0.72, y: 0.16),
             side: .leading),
        // Middle orbit, just past the waist so their labels clear the
        // wordmark hanging under the sun.
        Star(id: "journeys", destination: .journeys, title: "Long\nStrange Trip",
             style: .comet, bodySize: 44, position: UnitPoint(x: 0.24, y: 0.63),
             side: .bottom),
        Star(id: "songs", destination: .songs, title: "Songs",
             style: .spiral, bodySize: 52, position: UnitPoint(x: 0.76, y: 0.63),
             side: .bottom),
        // Inner orbit, due south.
        Star(id: "topShelf", destination: .topShelf, title: "Top Shelf",
             style: .earthlike, bodySize: 46, position: UnitPoint(x: 0.50, y: 0.82),
             side: .bottom, tint: Color(red: 1.0, green: 0.86, blue: 0.42)),
    ]

    /// Scenery. Unlabelled and untappable — balanced into the corners the
    /// orbits leave empty, one body per region.
    private let scenery: [(PlanetView.Style, CGFloat, UnitPoint)] = [
        (.redGiant, 26, UnitPoint(x: 0.13, y: 0.05)),
        (.galaxy, 34, UnitPoint(x: 0.87, y: 0.05)),
        (.marbled, 20, UnitPoint(x: 0.06, y: 0.30)),
        (.starburst, 38, UnitPoint(x: 0.94, y: 0.30)),
        (.nebula, 54, UnitPoint(x: 0.10, y: 0.93)),
        (.wireGlobe, 30, UnitPoint(x: 0.90, y: 0.93)),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackground()
                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height
                    ZStack {
                        // The orbits themselves: faint starlight ellipses.
                        ForEach(orbits.indices, id: \.self) { i in
                            Ellipse()
                                .strokeBorder(Theme.stroke.opacity(0.8), lineWidth: 1)
                                .frame(width: orbits[i].rx * 2 * w,
                                       height: orbits[i].ry * 2 * h)
                                .position(x: 0.5 * w, y: 0.5 * h)
                                .allowsHitTesting(false)
                        }

                        ForEach(scenery.indices, id: \.self) { i in
                            let (style, size, point) = scenery[i]
                            PlanetView(style: style, size: size)
                                .opacity(0.75)
                                .position(x: point.x * w, y: point.y * h)
                                .allowsHitTesting(false)
                        }

                        emblem
                            .position(x: 0.5 * w, y: 0.50 * h)

                        ForEach(stars) { star in
                            NavigationLink(value: star.destination) {
                                starLabel(star)
                            }
                            .buttonStyle(.plain)
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
    /// hung its logo in the middle of the solar system.
    private var emblem: some View {
        VStack(spacing: 6) {
            SpiralMandala(size: 116)
                .shadow(color: Theme.denim.opacity(0.5), radius: 26)
            Text("Deadhead AI")
                .font(Theme.display(21))
                .chromeText()
        }
        .allowsHitTesting(false)
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

        return Group {
            switch star.side {
            case .trailing:
                HStack(spacing: Self.labelGap) {
                    PlanetView(style: star.style, size: star.bodySize)
                    text.frame(width: Self.labelWidth, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
            case .leading:
                HStack(spacing: Self.labelGap) {
                    text.frame(width: Self.labelWidth, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                    PlanetView(style: star.style, size: star.bodySize)
                }
            case .bottom:
                VStack(spacing: Self.labelGap) {
                    PlanetView(style: star.style, size: star.bodySize)
                    text.frame(width: Self.labelWidth, height: Self.labelHeight, alignment: .top)
                        .multilineTextAlignment(.center)
                }
            case .top:
                VStack(spacing: Self.labelGap) {
                    text.frame(width: Self.labelWidth, height: Self.labelHeight, alignment: .bottom)
                        .multilineTextAlignment(.center)
                    PlanetView(style: star.style, size: star.bodySize)
                }
            }
        }
        .contentShape(Rectangle())
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

#Preview {
    RootView()
        .environment(AppEnvironment.mock())
        .preferredColorScheme(.dark)
}
