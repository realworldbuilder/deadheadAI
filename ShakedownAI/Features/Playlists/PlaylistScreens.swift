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
            if let playlist {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !playlist.blurb.isEmpty {
                            Text(playlist.blurb)
                                .font(.callout)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle(playlist?.name ?? "Mix Tape")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete Mix Tape", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this mix tape?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Mix Tape", role: .destructive) {
                if let playlist { env.library.deletePlaylist(playlist) }
                dismiss()
            }
        } message: {
            Text("The tracks stay on the archive — only the mix goes.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.title)
                .foregroundStyle(Theme.textTertiary)
            Text("Nothing on it yet. Long-press any tune on a show page — or select a few — and add them here.")
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
                Spacer()
                Text(minutes > 0 ? "\(count) · \(minutes) min" : count)
                    .font(Theme.subheadline)
                    .opacity(0.75)
            }
        }
        .buttonStyle(.primary(fullWidth: true))
    }

    private func trackRows(_ items: [PlaylistItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, item in
                Button {
                    engine.play(entries: items.map(\.queueEntry), startAt: index)
                } label: {
                    HStack(spacing: 10) {
                        Text(String(format: "%02d", index + 1))
                            .font(Theme.caption)
                            .foregroundStyle(isCurrent(item) ? Theme.accent : Theme.textTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.trackTitle)
                                .font(Theme.body)
                                .foregroundStyle(isCurrent(item) ? Theme.accent : Theme.textPrimary)
                                .lineLimit(1)
                            Text(item.showDisplayName)
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(displayDuration(item.durationSeconds))
                            .font(Theme.timecode)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .listRowStyle(divider: index < items.count - 1)
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
                        Label("Remove from Mix Tape", systemImage: "minus.circle")
                    }
                }
            }
        }
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
                                .foregroundStyle(Theme.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("A better order is hiding in here")
                                    .font(Theme.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Reorder so the real segue pairs sit next to each other, the way the boys played them.")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text("Apply")
                                .font(Theme.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(Theme.cardPadding)
                        .cardStyle()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 0) {
                    ForEach(Array(picks.enumerated()), id: \.element.songKey) { index, pick in
                        pickRow(pick, playlist: playlist, divider: index < picks.count - 1)
                    }
                }
            }
        }
    }

    private func pickRow(_ pick: SegueSuggester.NextPick, playlist: Playlist, divider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
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
                ProgressView().tint(Theme.textSecondary).scaleEffect(0.8)
            case .added(let source):
                Label("Added from \(source)", systemImage: "checkmark.circle.fill")
                    .font(Theme.caption.weight(.semibold))
                    .foregroundStyle(Theme.sage)
            case .failed:
                Text("Couldn't find a tape with it just now.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            case nil:
                if pick.famousDate != nil {
                    Button {
                        Task { await addPick(pick, playlist: playlist) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                            Text("Find a version & add it")
                                .font(Theme.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .listRowStyle(divider: divider)
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
        let items = (playlist.items ?? []).sorted { $0.sortIndex < $1.sortIndex }
        LibraryTile(
            name: playlist.name,
            detail: "\(items.count) track\(items.count == 1 ? "" : "s")",
            icon: playlist.iconName,
            cover: items.first.map { Show(identifier: $0.showIdentifier, title: $0.showDisplayName,
                                          date: IADates.parse($0.showDateString),
                                          dateString: $0.showDateString, venue: $0.showDisplayName,
                                          location: nil, year: Int($0.showDateString.prefix(4)),
                                          avgRating: nil, numReviews: nil, downloads: nil, source: nil) }
        )
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
            VStack(alignment: .leading, spacing: 16) {
                TextField("Mix tape name", text: $name)
                    .font(Theme.body)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                TextField("What's it for? (optional)", text: $blurb)
                    .font(Theme.body)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                Text("Icon")
                    .eyebrowStyle()
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
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(icon == candidate ? Color.clear : Theme.stroke, lineWidth: 1)
                                )
                        }
                        .accessibilityLabel(candidate.replacingOccurrences(of: ".", with: " "))
                        .accessibilityAddTraits(icon == candidate ? .isSelected : [])
                    }
                }
                Spacer()
            }
            .padding(Theme.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("New Mix Tape")
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
        .presentationBackground(Theme.background)
    }
}
