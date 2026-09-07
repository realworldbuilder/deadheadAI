import OSLog
import SwiftUI

enum AppTab: String {
    case home, explore, chat, library, settings
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showingOnboarding = false
    @State private var stagedShow: Show?
    @State private var stagedYear: StagedYear?
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

        tabs
            .background(Theme.background)
            .overlay(alignment: .top) { ArchiveOfflineBanner() }
            .environment(env.playerEngine)
            .sensoryFeedback(.impact(weight: .light), trigger: engine.state,
                             condition: Self.playPauseToggled)
            .sheet(isPresented: $engine.isPresentingFullPlayer) {
                PlayerScreen()
                    .environment(env.playerEngine)
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                if !didOnboard { showingOnboarding = true }
            }
            .sheet(isPresented: $showingOnboarding, onDismiss: { didOnboard = true }) {
                OnboardingSheet()
            }
            .task {
                env.library.dedupAfterSync()
                await env.authProvider.refresh()
                await env.sync.syncNow()
                await stageForScreenshotsIfRequested()
                await runDemoAutoplayIfRequested()
                await runDemoDownloadIfRequested()
            }
            .fullScreenCover(item: $stagedShow) { show in
                NavigationStack {
                    ShowDetailScreen(show: show)
                        .toolbar {
                            // The staging cover must never trap a human who
                            // wanders into a simulator left in this mode.
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    stagedShow = nil
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .accessibilityLabel("Close staged show")
                            }
                        }
                }
                .environment(env.playerEngine)
            }
            .fullScreenCover(item: $stagedYear) { staged in
                NavigationStack {
                    YearScreen(year: staged.year, count: staged.count)
                        .navigationDestination(for: Show.self) { ShowDetailScreen(show: $0) }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    stagedYear = nil
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .accessibilityLabel("Close staged year")
                            }
                        }
                }
                .environment(env.playerEngine)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    env.library.dedupAfterSync()
                    Task { await env.sync.syncNow() }
                }
            }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeScreen()
            }
            Tab("Explore", systemImage: "map.fill", value: .explore) {
                ExploreTabView()
            }
            Tab("Nethead", systemImage: "bubble.left.and.text.bubble.right.fill", value: .chat) {
                ChatScreen()
            }
            Tab("Library", systemImage: "books.vertical.fill", value: .library) {
                LibraryScreen()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                SettingsScreen()
            }
        }
    }

    /// Haptic only on a deliberate pause/resume. Auto-advance passes through
    /// .loading between tracks, and this must not buzz on every song of a
    /// three-hour show.
    private static func playPauseToggled(from old: PlayerEngine.PlaybackState,
                                         to new: PlayerEngine.PlaybackState) -> Bool {
        (old == .playing && new == .paused)
            || ((old == .paused || old == .finished) && new == .playing)
    }

    private struct StagedYear: Identifiable {
        let year: Int
        let count: Int
        var id: Int { year }
    }

    /// Debug hooks for CLI screenshot staging: `--stage-show` opens the best
    /// Cornell '77 source's show page; `--stage-player` starts it streaming
    /// and presents the full-screen player; `--stage-year 1977` opens that
    /// year's month-by-month browse; `--stage-show 1972-05-04` picks another
    /// night, and `--stage-scans` opens the scan viewer on top. All drive
    /// the real UI so captures show live data.
    private func stageForScreenshotsIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--stage-year"), index + 1 < args.count,
           let year = Int(args[index + 1]) {
            let count = await env.catalog.yearCounts().first { $0.year == year }?.count ?? 0
            stagedYear = StagedYear(year: year, count: count)
            return
        }
        guard args.contains("--stage-show") || args.contains("--stage-player") else { return }
        // `--stage-show 1972-05-04` stages another night (say, one with no scans).
        var date = "1977-05-08"
        if let index = args.firstIndex(of: "--stage-show"), index + 1 < args.count,
           args[index + 1].count == 10, args[index + 1].hasPrefix("19") {
            date = args[index + 1]
        }
        guard let best = (try? await env.recordingProvider.recordings(forDate: date))?.first else { return }
        if args.contains("--stage-show") {
            stagedShow = best
            return
        }
        guard let detail = try? await env.metadataProvider.detail(for: best.identifier) else { return }
        env.playerEngine.play(show: best, tracks: detail.tracks)
        try? await Task.sleep(for: .seconds(2))
        env.playerEngine.isPresentingFullPlayer = true
    }

    /// Debug hook: `--demo-download` downloads the best Cornell '77 source and
    /// logs per-track progress, so the offline pipeline is verifiable from the
    /// CLI via `log show --predicate 'subsystem == "ai.deadheads"'` plus the
    /// files landing in the app container.
    private func runDemoDownloadIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--demo-download") else { return }
        let log = Logger(subsystem: "ai.deadheads", category: "demo")
        do {
            let shows = try await env.recordingProvider.recordings(forDate: "1977-05-08")
            guard let best = shows.first else {
                log.error("DEMO-DL: no recordings found")
                return
            }
            let detail = try await env.metadataProvider.detail(for: best.identifier)
            log.notice("DEMO-DL: downloading \(best.identifier, privacy: .public) tracks=\(detail.tracks.count)")
            env.downloads.download(show: best, detail: detail)
            for _ in 0..<120 {
                try await Task.sleep(for: .seconds(2))
                let state = env.downloads.displayState(for: best.identifier)
                log.notice("DEMO-DL: state=\(String(describing: state), privacy: .public)")
                switch state {
                case .downloaded, .failed: return
                default: continue
                }
            }
        } catch {
            log.error("DEMO-DL: error \(String(describing: error), privacy: .public)")
        }
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

#Preview {
    RootView()
        .environment(AppEnvironment.mock())
}
