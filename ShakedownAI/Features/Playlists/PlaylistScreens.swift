import SwiftUI
import SwiftData

/// Routing wrapper so playlists don't collide with the collection route,
/// which already owns `navigationDestination(for: PersistentIdentifier.self)`.
nonisolated struct PlaylistRoute: Hashable {
    let id: PersistentIdentifier
}

// MARK: - Playlist detail

struct PlaylistDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(PlayerEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let playlistID: PersistentIdentifier
    @State private var refreshToken = 0
    @State private var confirmingDelete = false
    @State private var pickStatus: [String: PickStatus] = [:]

    private enum PickStatus: Equatable {
        case loading
        case added(String)   // the show it was pulled from
        case failed
    }

    private var playlist: Playlist? {
        modelContext.model(for: playlistID) as? Playlist
    }

    var body: some View {
        ZStack {
            SpaceBackground()
            if let playlist {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !playlist.blurb.isEmpty {
                            Text(playlist.blurb)
                                .font(.system(.callout, design: .serif).italic())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        let _ = refreshToken
                        let items = env.library.sortedItems(of: playlist)
                        if items.isEmpty {
                            emptyState
                        } else {
                            playAllButton(items)
                            trackRows(items)
                            flowSection(playlist, items: items)
                        }
                    }
                    .padding(Theme.screenPadding)
                }
                .withMiniPlayer()
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete Playlist", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this playlist?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) {
                if let playlist { env.library.deletePlaylist(playlist) }
                dismiss()
            }
        } message: {
            Text("The tracks stay in the archive — only the playlist goes.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.title)
                .foregroundStyle(Theme.textTertiary)
            Text("No tracks yet. Long-press any song on a show page — or select a few — and add them here.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private func playAllButton(_ items: [PlaylistItem]) -> some View {
        let totalSeconds = items.map(\.durationSeconds).reduce(0, +)
        let minutes = Int((totalSeconds / 60).rounded())
        let count = "\(items.count) track\(items.count == 1 ? "" : "s")"
        return Button {
            engine.play(entries: items.map(\.queueEntry))
            engine.isPresentingFullPlayer = true
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("Play All")
                    .font(Theme.mono(15, weight: .bold))
                Spacer()
                Text(minutes > 0 ? "\(count) · \(minutes) min" : count)
                    .font(Theme.mono(12))
                    .opacity(0.75)
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.accentGradient)
            )
        }
    }

    private func trackRows(_ items: [PlaylistItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, item in
                Button {
                    engine.play(entries: items.map(\.queueEntry), startAt: index)
                } label: {
                    HStack(spacing: 10) {
                        Text(String(format: "%02d", index + 1))
                            .font(Theme.mono(12))
                            .foregroundStyle(isCurrent(item) ? Theme.accent : Theme.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.trackTitle)
                                .font(Theme.body)
                                .foregroundStyle(isCurrent(item) ? Theme.accent : Theme.textPrimary)
                                .lineLimit(1)
                            Text(item.showDisplayName)
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(displayDuration(item.durationSeconds))
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.vertical, 11)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        env.library.move(item: item, up: true)
                        refreshToken += 1
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    .disabled(index == 0)
                    Button {
                        env.library.move(item: item, up: false)
                        refreshToken += 1
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                    .disabled(index == items.count - 1)
                    NavigationLink(value: item.queueEntry.show) {
                        Label("Go to Show", systemImage: "arrow.right.circle")
                    }
                    Button(role: .destructive) {
                        env.library.remove(item: item)
                        refreshToken += 1
                    } label: {
                        Label("Remove from Playlist", systemImage: "minus.circle")
                    }
                }
                if index < items.count - 1 {
                    Divider().overlay(Theme.stroke.opacity(0.5)).padding(.leading, 34)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Flow (deterministic segue suggestions)

    /// KB-grounded next-track picks and a better ordering when one exists.
    /// Every suggestion resolves to a real fetched track before it's added.
    @ViewBuilder
    private func flowSection(_ playlist: Playlist, items: [PlaylistItem]) -> some View {
        let picks = SegueSuggester.nextPicks(after: items.map(\.songKey), kb: env.knowledgeBase)
        let order = SegueSuggester.suggestedOrder(
            for: items.map { (key: $0.trackKey, songKey: $0.songKey) },
            kb: env.knowledgeBase)
        if !picks.isEmpty || order != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Flow").sectionHeaderStyle()
                if let order {
                    Button {
                        env.library.reorder(playlist, toTrackKeys: order)
                        refreshToken += 1
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.swap")
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("A better order is hiding in here")
                                    .font(Theme.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Reorder so the true segue pairs sit next to each other, the way the band played them.")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text("Apply")
                                .font(Theme.mono(12, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(13)
                        .cardStyle(raised: true)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(picks, id: \.songKey) { pick in
                    pickCard(pick, playlist: playlist)
                }
            }
        }
    }

    private func pickCard(_ pick: SegueSuggester.NextPick, playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                Text(pick.title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            Text(pick.reason)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            switch pickStatus[pick.songKey] {
            case .loading:
                ProgressView().tint(Theme.accent).scaleEffect(0.8)
            case .added(let source):
                Label("Added from \(source)", systemImage: "checkmark.circle.fill")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.sage)
            case .failed:
                Text("Couldn't find a tape with it just now.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
            case nil:
                if pick.famousDate != nil {
                    Button {
                        Task { await addPick(pick, playlist: playlist) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                            Text("Find a version & add it")
                                .font(Theme.mono(12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func addPick(_ pick: SegueSuggester.NextPick, playlist: Playlist) async {
        guard let date = pick.famousDate else { return }
        pickStatus[pick.songKey] = .loading
        guard let shows = try? await env.recordingProvider.recordings(forDate: date),
              let best = shows.first,
              let detail = try? await env.metadataProvider.detail(for: best.identifier),
              let track = detail.tracks.first(where: { trackMatches($0, songKey: pick.songKey) }) else {
            pickStatus[pick.songKey] = .failed
            return
        }
        env.library.add(tracks: [track], from: best, to: playlist)
        pickStatus[pick.songKey] = .added(best.displayDate)
        refreshToken += 1
    }

    private func trackMatches(_ track: Track, songKey: String) -> Bool {
        let key = track.songKey
        return key == songKey || (" " + key + " ").contains(" " + songKey + " ")
    }

    private func isCurrent(_ item: PlaylistItem) -> Bool {
        engine.currentShow?.identifier == item.showIdentifier
            && engine.currentTrack?.fileName == item.fileName
    }

    private func displayDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Playlist card (Library grid)

struct PlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: playlist.iconName)
                .font(.title3)
                .foregroundStyle(Theme.accent)
            Text(playlist.name)
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text("\(playlist.items?.count ?? 0) track\((playlist.items?.count ?? 0) == 1 ? "" : "s")")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - New playlist sheet

struct NewPlaylistSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var blurb = ""
    @State private var icon = "music.note.list"

    private static let icons = ["music.note.list", "waveform", "flame.fill", "heart.fill",
                                "car.fill", "moon.stars.fill", "sun.horizon.fill",
                                "bolt.fill", "guitars.fill", "infinity"]

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackground()
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Playlist name", text: $name)
                        .font(Theme.body)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                    TextField("What's the vibe? (optional)", text: $blurb)
                        .font(Theme.body)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                    Text("ICON")
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Self.icons, id: \.self) { candidate in
                            Button {
                                icon = candidate
                            } label: {
                                Image(systemName: candidate)
                                    .font(.title3)
                                    .foregroundStyle(icon == candidate ? Theme.accent : Theme.textSecondary)
                                    .frame(width: 46, height: 46)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(icon == candidate ? Theme.accent.opacity(0.15) : Theme.surface)
                                    )
                            }
                            .accessibilityLabel(candidate.replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(icon == candidate ? .isSelected : [])
                        }
                    }
                    Spacer()
                }
                .padding(Theme.screenPadding)
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        env.library.createPlaylist(name: name, blurb: blurb, iconName: icon)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
