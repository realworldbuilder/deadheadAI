import SwiftUI
import SwiftData

struct LibraryScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingNewCollection = false
    @State private var refreshToken = 0

    private enum Destination: Hashable {
        case journal, history, taste, friends
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SmartShelfSection()
                        collectionsSection
                        linksSection
                    }
                    .padding(Theme.screenPadding)
                }
                .withMiniPlayer()
            }
            .navigationTitle("Library")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .journal: JournalListScreen()
                case .history: HistoryScreen()
                case .taste: TasteProfileScreen()
                case .friends: FriendsScreen()
                }
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                CollectionDetailScreen(collectionID: id)
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
        .tint(Theme.accent)
        .onAppear {
            env.library.seedDefaultCollectionsIfNeeded()
            refreshToken += 1
        }
        .sheet(isPresented: $showingNewCollection, onDismiss: { refreshToken += 1 }) {
            NewCollectionSheet()
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
                        .foregroundStyle(Theme.accent)
                }
            }
            let collections = env.library.collections
            let _ = refreshToken   // re-read after sheet dismissals
            if collections.isEmpty {
                Text("Make shelves for the shows that matter — road trips, Sunday mornings, Jerry destroying it.")
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
        VStack(spacing: 10) {
            NavigationLink(value: Destination.journal) {
                libraryRow(icon: "book.closed.fill", title: "Journal",
                           subtitle: "Memories tied to music.")
            }
            NavigationLink(value: Destination.history) {
                libraryRow(icon: "clock.arrow.circlepath", title: "Listening History",
                           subtitle: "Every night you've spent in the archive.")
            }
            NavigationLink(value: Destination.taste) {
                libraryRow(icon: "chart.bar.fill", title: "Taste Profile",
                           subtitle: "What the app has learned about your ears.")
            }
            NavigationLink(value: Destination.friends) {
                libraryRow(icon: "person.2.fill", title: "Friends",
                           subtitle: "Compare taste, share shows, listen together.")
            }
        }
        .buttonStyle(.plain)
    }

    private func libraryRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
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
        .padding(14)
        .cardStyle()
    }
}

// MARK: - Collection card & detail

private struct CollectionCard: View {
    let collection: ShowCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: collection.iconName)
                .font(.title3)
                .foregroundStyle(Theme.accent)
            Text(collection.name)
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text("\(collection.items.count) show\(collection.items.count == 1 ? "" : "s")")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(raised: true)
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
            SpaceBackground()
            if let collection {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !collection.blurb.isEmpty {
                            Text(collection.blurb)
                                .font(.system(.callout, design: .serif).italic())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        let _ = refreshToken
                        let items = collection.items.sorted { $0.sortIndex < $1.sortIndex }
                        if items.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "square.stack.3d.up.slash")
                                    .font(.title)
                                    .foregroundStyle(Theme.textTertiary)
                                Text("Nothing shelved yet. Save shows here from any show page.")
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 50)
                        }
                        ForEach(items, id: \.persistentModelID) { item in
                            NavigationLink(value: stubShow(for: item)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.displayName)
                                            .font(Theme.headline)
                                            .foregroundStyle(Theme.textPrimary)
                                            .lineLimit(2)
                                        Text("Added \(item.addedAt.formatted(date: .abbreviated, time: .omitted))")
                                            .font(Theme.mono(11))
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
                                }
                                .padding(12)
                                .cardStyle()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.screenPadding)
                }
                .withMiniPlayer()
            }
        }
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
            let count = collection?.items.count ?? 0
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
            ZStack {
                SpaceBackground()
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Collection name", text: $name)
                        .font(Theme.body)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                    TextField("What belongs here? (optional)", text: $blurb)
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
                        }
                    }
                    Spacer()
                }
                .padding(Theme.screenPadding)
            }
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
    }
}
