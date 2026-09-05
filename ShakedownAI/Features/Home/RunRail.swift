import OSLog
import SwiftUI

/// The home page's runs: a few nights' worth of the curated canon plus the
/// runs the catalog found on the best-rated tapes, each playable on its own
/// (just the run, nothing before or after) or all stitched into one queue.
@Observable
final class RunShelfModel {

    struct Pick: Identifiable, Hashable {
        let run: FamousRun
        /// The night's best tape when the catalog knows it; otherwise
        /// resolved at play time, so the shelf itself never touches the network.
        let show: Show?
        let venue: String?
        let location: String?
        let isCanon: Bool

        var id: String { run.id }

        /// "Famous run · 2 songs" / "Set 2 · 3 songs" / "Famous run · one long version"
        var badge: String {
            let songs = run.songKeys.filter { !RunFinder.isBridge($0) }.count
            let length = songs <= 1 ? "one long version" : "\(songs) songs"
            if isCanon { return "Famous run · \(length)" }
            let set = run.tags.contains("marathon") ? "Marathon" : "Segue"
            return "\(set) · \(length)"
        }
    }

    private(set) var picks: [Pick] = []
    /// Each pick pinned to a real tape once the archive has answered — the
    /// source of the card's running time and of instant playback.
    private(set) var resolved: [String: ResolvedRun] = [:]
    /// Picks no reachable tape carries in one piece.
    private(set) var unavailable: Set<String> = []
    private(set) var isResolving = false
    private(set) var startingRunID: String?
    private(set) var isStitching = false
    var error: String?

    private let env: AppEnvironment
    private var loadedForDay: Int?
    private static let log = Logger(subsystem: "ai.deadheads", category: "runs")

    static let canonCount = 3
    static let catalogCount = 4
    /// How many of the catalog's best-rated nights to search for runs.
    static let catalogSearchDepth = 60

    init(env: AppEnvironment) {
        self.env = env
    }

    func load() async {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 1
        guard loadedForDay != dayOfYear else { return }
        loadedForDay = dayOfYear

        let kb = env.knowledgeBase
        let canon = RunShelfPlanner.canonPicks(kb.runs, dayOfYear: dayOfYear,
                                               taste: env.history.tasteSnapshot, limit: Self.canonCount)
        var result: [Pick] = []
        for run in canon {
            let night = env.catalog.isAvailable ? await env.catalog.show(onDate: run.date) : nil
            let notable = kb.notableShow(on: run.date)
            result.append(Pick(run: run,
                               show: night?.asShow,
                               venue: night?.venue ?? notable?.venue,
                               location: night?.location ?? notable?.location,
                               isCanon: true))
        }

        if env.catalog.isAvailable {
            var candidates: [RunShelfPlanner.Candidate] = []
            for night in await env.catalog.topRated(yearRange: nil, limit: Self.catalogSearchDepth) {
                guard let setlist = await env.catalog.setlist(forShow: night.showID) else { continue }
                let entries = setlist.sets.flatMap(\.entries)
                for chain in RunFinder.chains(in: entries, kb: kb) {
                    candidates.append(.init(chain: chain, show: night))
                }
            }
            let byDate = Dictionary(candidates.map { ($0.show.date, $0.show) }, uniquingKeysWith: { first, _ in first })
            let found = RunShelfPlanner.catalogPicks(candidates,
                                                     excludingDates: Set(canon.map(\.date)),
                                                     dayOfYear: dayOfYear, limit: Self.catalogCount)
            for run in found {
                let night = byDate[run.date]
                result.append(Pick(run: run, show: night?.asShow, venue: night?.venue,
                                   location: night?.location, isCanon: false))
            }
        }
        picks = result
        await resolveAll()
    }

    /// Pins every pick to a tape, shelf order, so the cards can say how long
    /// each run is. Network once per tape, then the detail cache answers.
    func resolveAll() async {
        guard !isResolving else { return }
        isResolving = true
        defer { isResolving = false }
        for pick in picks where resolved[pick.id] == nil && !unavailable.contains(pick.id) {
            if let hit = try? await resolve(pick) {
                resolved[pick.id] = hit
            } else {
                unavailable.insert(pick.id)
            }
        }
    }

    /// "26 min" once the run is pinned to a tape.
    func lengthText(for pick: Pick) -> String? {
        resolved[pick.id]?.lengthText
    }

    /// The whole shelf end to end, once every reachable run is pinned.
    var totalLengthText: String? {
        let known = picks.compactMap { resolved[$0.id]?.seconds }
        guard !known.isEmpty, known.count + unavailable.count >= picks.count else { return nil }
        return RunLength.format(seconds: known.reduce(0, +))
    }

    /// Tests hand the shelf a fixed set of picks instead of the day's plan.
    func setPicksForTesting(_ picks: [Pick]) {
        self.picks = picks
        resolved = [:]
        unavailable = []
    }

    // MARK: - Playback

    /// Plays the run and only the run: the queue is the run's tracks.
    func play(_ pick: Pick) async {
        guard startingRunID == nil, !isStitching else { return }
        startingRunID = pick.id
        error = nil
        defer { startingRunID = nil }
        do {
            let hit = try await resolvedRun(for: pick)
            env.playerEngine.play(entries: hit.entries)
            env.playerEngine.isPresentingFullPlayer = true
        } catch {
            self.error = message(for: error, pick: pick)
        }
    }

    /// Stitches every run on the shelf into one queue, in shelf order,
    /// skipping any whose tape doesn't line up. Each entry carries its own
    /// show, so Now Playing and history attribute every track correctly.
    func playAll() async {
        guard !isStitching, startingRunID == nil, !picks.isEmpty else { return }
        isStitching = true
        error = nil
        defer { isStitching = false }

        var entries: [PlayerQueueEntry] = []
        var skipped = 0
        var outage = false
        for pick in picks {
            do {
                entries += try await resolvedRun(for: pick).entries
            } catch HTTPError.serviceUnavailable {
                outage = true
                break
            } catch {
                skipped += 1
            }
        }

        guard !entries.isEmpty else {
            error = outage ? ArchiveHealth.outageMessage
                : "Couldn't line up any of these runs on their tapes right now. Check your connection and try again."
            return
        }
        env.playerEngine.play(entries: entries)
        env.playerEngine.isPresentingFullPlayer = true
        if skipped > 0 {
            error = "Stitched \(picks.count - skipped) of \(picks.count) runs — the rest aren't on any tape we can reach."
        }
    }

    private enum RunError: Error {
        case noTape
        case notOnThisTape
    }

    /// The pinned tape when we have it; otherwise resolve now and remember.
    private func resolvedRun(for pick: Pick) async throws -> ResolvedRun {
        if let hit = resolved[pick.id] { return hit }
        do {
            let hit = try await resolve(pick)
            resolved[pick.id] = hit
            return hit
        } catch RunError.notOnThisTape {
            unavailable.insert(pick.id)
            throw RunError.notOnThisTape
        }
    }

    /// How many of a night's tapes to try before giving up on a run.
    static let tapesToTry = 4

    /// The run on a real tape: the night's best tape first, then the rest of
    /// the night's tapes best-first, because a best tape can be a partial —
    /// set one only, or a transfer that stops before the run.
    private func resolve(_ pick: Pick) async throws -> ResolvedRun {
        if let hit = await resolveFromCatalog(pick) { return hit }
        return try await resolveFromArchive(pick)
    }

    /// The catalog carries the tracks of the top tapes per show, so most
    /// runs pin to a tape — file names, running time and all — with no
    /// network. The pick's own tape goes first; the night's others follow
    /// in quality order.
    private func resolveFromCatalog(_ pick: Pick) async -> ResolvedRun? {
        guard env.catalog.isAvailable else { return nil }
        var showID: String?
        if let known = pick.show {
            showID = await env.catalog.recording(identifier: known.identifier)?.showID
        }
        if showID == nil {
            showID = await env.catalog.show(onDate: pick.run.date)?.showID
        }
        guard let showID else { return nil }
        var tapes = await env.catalog.recordings(forShow: showID)
        if let known = pick.show, let index = tapes.firstIndex(where: { $0.identifier == known.identifier }), index > 0 {
            tapes.insert(tapes.remove(at: index), at: 0)
        }
        let night = await env.catalog.show(withID: showID)
        for tape in tapes.prefix(Self.tapesToTry) {
            guard let tracks = await env.catalog.tracks(forRecording: tape.identifier),
                  let range = RunResolver.resolve(pick.run, in: tracks) else { continue }
            let show = pick.show?.identifier == tape.identifier
                ? pick.show!
                : Self.show(for: tape, night: night)
            return ResolvedRun(run: pick.run, show: show, tracks: tracks, range: range)
        }
        return nil
    }

    /// A playable `Show` for one of the night's tapes, wearing the night's
    /// venue and date so Now Playing reads right.
    private static func show(for tape: CatalogRecording, night: CatalogShow?) -> Show {
        guard let night, var show = night.asShow else { return tape.asShow }
        show.identifier = tape.identifier
        show.title = tape.title ?? show.title
        show.avgRating = tape.avgRating
        show.numReviews = tape.numReviews
        show.downloads = tape.downloads
        show.source = tape.sourceText
        return show
    }

    private func resolveFromArchive(_ pick: Pick) async throws -> ResolvedRun {
        var tried = Set<String>()
        var candidates: [Show] = pick.show.map { [$0] } ?? []
        var fetchedOthers = false

        while true {
            if candidates.isEmpty {
                guard !fetchedOthers else { break }
                fetchedOthers = true
                let others = try await env.recordingProvider.recordings(forDate: pick.run.date)
                candidates = others.filter { !tried.contains($0.identifier) }
                if candidates.isEmpty { break }
            }
            let show = candidates.removeFirst()
            guard tried.insert(show.identifier).inserted, tried.count <= Self.tapesToTry else { continue }
            let detail = try await env.metadataProvider.detail(for: show.identifier)
            if let range = RunResolver.resolve(pick.run, in: detail.tracks) {
                return ResolvedRun(run: pick.run, show: show, tracks: detail.tracks, range: range)
            }
            let titles = detail.tracks.map(\.title).joined(separator: " | ")
            Self.log.notice("Run \(pick.run.id, privacy: .public) not on \(show.identifier, privacy: .public): \(titles, privacy: .public)")
        }
        throw tried.isEmpty ? RunError.noTape : RunError.notOnThisTape
    }

    private func message(for error: any Error, pick: Pick) -> String {
        switch error {
        case HTTPError.serviceUnavailable:
            return ArchiveHealth.outageMessage
        case RunError.noTape:
            return "Couldn't find a tape for \(LocalKnowledgeAI.prettyDate(pick.run.date)) right now."
        case RunError.notOnThisTape:
            return "None of the tapes we can reach carry \(pick.run.title) in one piece — open the show to explore it."
        default:
            return "Couldn't reach the archive. Check your connection and try again."
        }
    }
}

// MARK: - Rail

struct RunRail: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: RunShelfModel?

    var body: some View {
        // The container is always present, even while the shelf is empty:
        // modifiers on an empty view never fire, so an empty Group would
        // never start the load.
        VStack(alignment: .leading, spacing: 10) {
            if let model, !model.picks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "flame")
                            .foregroundStyle(Theme.textSecondary)
                        Text("The Runs").sectionHeaderStyle()
                        Spacer()
                        Button {
                            Task { await model.playAll() }
                        } label: {
                            HStack(spacing: 5) {
                                if model.isStitching {
                                    ProgressView().tint(Theme.textSecondary).scaleEffect(0.7)
                                } else {
                                    Image(systemName: "play.fill").font(.caption)
                                }
                                Text("Play all")
                            }
                        }
                        .buttonStyle(.secondary)
                        .disabled(model.isStitching || model.startingRunID != nil)
                        .accessibilityLabel("Play all runs, stitched together")
                    }
                    Text(subtitle(total: model.totalLengthText))
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(model.picks) { pick in
                                RunCard(pick: pick,
                                        lengthText: model.lengthText(for: pick),
                                        isUnavailable: model.unavailable.contains(pick.id),
                                        isStarting: model.startingRunID == pick.id) {
                                    Task { await model.play(pick) }
                                }
                            }
                        }
                    }
                    .scrollClipDisabled()
                    if let error = model.error {
                        Text(error)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.rose)
                    }
                }
            }
        }
        .task {
            if model == nil { model = RunShelfModel(env: env) }
            await model?.load()
        }
    }

    /// The shelf's running time joins the blurb once every tape has answered.
    private func subtitle(total: String?) -> String {
        var text = "Segues and marathons — the stretches inside a night that people never stop talking about, each playable on its own."
        if let total { text += " Today's shelf runs \(total) end to end." }
        return text
    }
}

/// One run on the shelf: the night's scan, the sequence with its arrows,
/// where it happened, and a play button that plays just this run.
struct RunCard: View {
    let pick: RunShelfModel.Pick
    /// "26 min" once the run is pinned to a tape; nil while the archive answers.
    var lengthText: String?
    /// No reachable tape carries this run in one piece.
    var isUnavailable = false
    let isStarting: Bool
    let onPlay: () -> Void

    private let width: CGFloat = 236

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: pick.run) {
                VStack(alignment: .leading, spacing: 6) {
                    DateCover(date: pick.run.date, identifier: pick.show?.identifier,
                              venue: pick.venue, cornerRadius: 10)
                        .frame(width: width, height: 132)
                    Self.styledTitle(pick.run.title)
                        .font(Theme.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(placeLine)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Text(badgeLine)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isUnavailable {
                Text("Not on any tape we can reach")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 2)
            } else {
                Button(action: onPlay) {
                    HStack(spacing: 6) {
                        if isStarting {
                            ProgressView().tint(Theme.textSecondary).scaleEffect(0.7)
                        } else {
                            Image(systemName: "play.circle.fill")
                        }
                        Text("Play the run")
                            .font(Theme.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
                .disabled(isStarting)
                .accessibilityLabel("Play \(pick.run.title)\(lengthText.map { ", \($0)" } ?? "")")
            }
        }
        .frame(width: width, alignment: .leading)
    }

    /// "Famous run · 2 songs · 26 min" — the time joins once the tape has answered.
    private var badgeLine: String {
        [pick.badge, lengthText].compactMap { $0 }.joined(separator: " · ")
    }

    private var placeLine: String {
        [LocalKnowledgeAI.prettyDate(pick.run.date), pick.venue]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// The run's title with every segue arrow in denim, the way the
    /// setlist draws them.
    static func styledTitle(_ title: String) -> Text {
        let parts = title.components(separatedBy: " > ")
        guard parts.count > 1 else {
            return Text(title).foregroundStyle(Theme.textPrimary)
        }
        var text = Text("")
        for (index, part) in parts.enumerated() {
            if index > 0 {
                text = text + Text(" > ").foregroundStyle(Theme.denim)
            }
            text = text + Text(part).foregroundStyle(Theme.textPrimary)
        }
        return text
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            RunRail()
                .padding(Theme.screenPadding)
        }
        .background(Theme.background)
    }
    .environment(AppEnvironment.mock())
}
