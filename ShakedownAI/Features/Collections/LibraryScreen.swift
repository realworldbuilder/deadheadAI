import SwiftUI
import SwiftData

struct LibraryScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingNewCollection = false
    @State private var showingNewPlaylist = false
    @State private var refreshToken = 0

    private enum Destination: Hashable {
        case years, journal, history, taste, downloads
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    SmartShelfSection()
                    playlistsSection
                    collectionsSection
                    ShelvesSignInNudge()
                    linksSection
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.background)
            .withMiniPlayer()
            .navigationTitle("Library")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .years: BrowseScreen()
                case .journal: JournalListScreen()
                case .history: HistoryScreen()
                case .taste: TasteProfileScreen()
                case .downloads: DownloadsScreen()
                }
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                CollectionDetailScreen(collectionID: id)
            }
            .navigationDestination(for: PlaylistRoute.self) { route in
                PlaylistDetailScreen(playlistID: route.id)
            }
            .navigationDestination(for: SmartCollection.self) { collection in
                SmartCollectionDetailScreen(collection: collection)
            }
            .navigationDestination(for: NotableShow.self) { notable in
                NotableShowResolverScreen(notable: notable)
            }
            .navigationDestination(for: Show.self) { show in
                ShowDetailScreen(show: show)
            }
        }
        .tint(Theme.textPrimary)
        .onAppear {
            env.library.seedDefaultCollectionsIfNeeded()
            refreshToken += 1
        }
        .sheet(isPresented: $showingNewCollection, onDismiss: { refreshToken += 1 }) {
            NewCollectionSheet()
        }
        .sheet(isPresented: $showingNewPlaylist, onDismiss: { refreshToken += 1 }) {
            NewPlaylistSheet()
        }
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mix Tapes").sectionHeaderStyle()
                Spacer()
                Button {
                    showingNewPlaylist = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textPrimary)
                }
                .accessibilityLabel("New mix tape")
            }
            let playlists = env.library.playlists
            let _ = refreshToken   // re-read after sheet dismissals
            if playlists.isEmpty {
                Text("Roll your own mix tape — any tune from any show. Long-press a track on a show page to start one.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(playlists, id: \.persistentModelID) { playlist in
                    NavigationLink(value: PlaylistRoute(id: playlist.persistentModelID)) {
                        PlaylistCard(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Collections").sectionHeaderStyle()
                Spacer()
                Button {
                    showingNewCollection = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textPrimary)
                }
                .accessibilityLabel("New collection")
            }
            let collections = env.library.collections
            let _ = refreshToken   // re-read after sheet dismissals
            if collections.isEmpty {
                Text("Shelves for the shows that matter — road trips, Sunday mornings, nights Jerry was on.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(collections, id: \.persistentModelID) { collection in
                    NavigationLink(value: collection.persistentModelID) {
                        CollectionCard(collection: collection)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var linksSection: some View {
        VStack(spacing: 0) {
            NavigationLink(value: Destination.years) {
                libraryRow(icon: "calendar", title: "Years",
                           subtitle: "Every show they played, '65 to '95 — find one by date.")
            }
            NavigationLink(value: Destination.journal) {
                libraryRow(icon: "book.closed.fill", title: "Journal",
                           subtitle: "Where you were, who you were with.")
            }
            NavigationLink(value: Destination.history) {
                libraryRow(icon: "clock.arrow.circlepath", title: "Listening History",
                           subtitle: "Every tape you've spun.")
            }
            NavigationLink(value: Destination.taste) {
                libraryRow(icon: "chart.bar.fill", title: "Taste Profile",
                           subtitle: "What Nethead has figured out about your ears.")
            }
            NavigationLink(value: Destination.downloads) {
                libraryRow(icon: "arrow.down.circle.fill", title: "Downloads",
                           subtitle: "Shows saved for the road — no signal needed.",
                           divider: false)
            }
        }
        .buttonStyle(.plain)
    }

    private func libraryRow(icon: String, title: String, subtitle: String,
                            divider: Bool = true) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .listRowStyle(divider: divider)
        .contentShape(Rectangle())
    }
}

// MARK: - Collection card & detail

private struct CollectionCard: View {
    let collection: ShowCollection

    var body: some View {
        let items = (collection.items ?? []).sorted { $0.sortIndex < $1.sortIndex }
        LibraryTile(
            name: collection.name,
            detail: "\(items.count) show\(items.count == 1 ? "" : "s")",
            icon: collection.iconName,
            cover: items.first.map { Show(identifier: $0.showIdentifier, title: $0.displayName,
                                          date: $0.showDate,
                                          dateString: $0.showDate.map { IADates.normalizedDayString(ISO8601DateFormatter().string(from: $0)) ?? "" },
                                          venue: $0.displayName, location: nil,
                                          year: $0.showDate.map { Calendar.current.component(.year, from: $0) },
                                          avgRating: nil, numReviews: nil, downloads: nil, source: nil) }
        )
    }
}

/// A grid tile for a collection or playlist: the cover of its first show
/// (its icon on an empty tile), the name, and a count.
struct LibraryTile: View {
    let name: String
    let detail: String
    let icon: String
    var cover: Show?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cover {
                ShowThumbnail(show: cover, size: 48)
            } else {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 48, height: 48)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .cardStyle()
    }
}

struct CollectionDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let collectionID: PersistentIdentifier
    @State private var refreshToken = 0
    @State private var confirmingDelete = false
    @State private var itemPendingRemoval: CollectionItem?
    @State private var confirmingRemoval = false

    private var collection: ShowCollection? {
        modelContext.model(for: collectionID) as? ShowCollection
    }

    var body: some View {
        ZStack {
            if let collection {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !collection.blurb.isEmpty {
                            Text(collection.blurb)
                                .font(.callout)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        let _ = refreshToken
                        let items = (collection.items ?? []).sorted { $0.sortIndex < $1.sortIndex }
                        if items.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "square.stack.3d.up.slash")
                                    .font(.title)
                                    .foregroundStyle(Theme.textTertiary)
                                Text("Nothing on this shelf yet. Save shows here from any show page.")
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 50)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.persistentModelID) { index, item in
                                NavigationLink(value: stubShow(for: item)) {
                                    HStack(spacing: 12) {
                                        ShowThumbnail(show: stubShow(for: item), size: 56)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.displayName)
                                                .font(Theme.headline)
                                                .foregroundStyle(Theme.textPrimary)
                                                .lineLimit(2)
                                            Text("Added \(item.addedAt.formatted(date: .abbreviated, time: .omitted))")
                                                .font(Theme.caption)
                                                .foregroundStyle(Theme.textTertiary)
                                        }
                                        Spacer()
                                        Button {
                                            itemPendingRemoval = item
                                            confirmingRemoval = true
                                        } label: {
                                            Image(systemName: "minus.circle")
                                                .foregroundStyle(Theme.rose)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove \(item.displayName) from collection")
                                    }
                                    .listRowStyle(divider: index < items.count - 1)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(Theme.screenPadding)
                }
                .withMiniPlayer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle(collection?.name ?? "Collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let collection {
                Menu {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete Collection", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Collection options")
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(collection?.name ?? "this collection")\u{201D}?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                if let collection {
                    env.library.deleteCollection(collection)
                    dismiss()
                }
            }
        } message: {
            let count = collection?.items?.count ?? 0
            Text("The shelf and its \(count) saved show\(count == 1 ? "" : "s") go with it. The recordings stay in the archive.")
        }
        .confirmationDialog(
            "Remove from this shelf?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible,
            presenting: itemPendingRemoval
        ) { item in
            Button("Remove Show", role: .destructive) {
                env.library.remove(item: item)
                refreshToken += 1
            }
        } message: { item in
            Text(item.displayName)
        }
        .sensoryFeedback(.warning, trigger: confirmingDelete) { !$0 && $1 }
        .sensoryFeedback(.warning, trigger: confirmingRemoval) { !$0 && $1 }
    }

    private func stubShow(for item: CollectionItem) -> Show {
        Show(identifier: item.showIdentifier, title: item.displayName,
             date: item.showDate,
             dateString: item.showDate.map { IADates.normalizedDayString(ISO8601DateFormatter().string(from: $0)) ?? "" },
             venue: item.displayName, location: nil,
             year: item.showDate.map { Calendar.current.component(.year, from: $0) },
             avgRating: nil, numReviews: nil, downloads: nil, source: nil)
    }
}

private struct NewCollectionSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var blurb = ""
    @State private var icon = "sparkles"

    private static let icons = ["sparkles", "heart.fill", "car.fill", "moon.stars.fill",
                                "sun.horizon.fill", "cloud.rain.fill", "flame.fill",
                                "bolt.fill", "guitars.fill", "infinity"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Collection name", text: $name)
                    .font(Theme.body)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                TextField("What belongs here? (optional)", text: $blurb)
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
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        env.library.createCollection(name: name, blurb: blurb, iconName: icon)
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
