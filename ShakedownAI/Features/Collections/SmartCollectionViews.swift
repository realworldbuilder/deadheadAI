import SwiftUI

// MARK: - Shelf section (Library)

/// The auto-curated shelves, rebuilt as the day and the listener's rotation move.
struct SmartShelfSection: View {
    @Environment(AppEnvironment.self) private var env
    @State private var engine: SmartCollectionEngine?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's Shelves").sectionHeaderStyle()
                Spacer()
                Button {
                    Task { await engine?.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .disabled(engine?.isRefreshing ?? true)
            }

            Text(subtitle)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)

            let collections = engine?.collections ?? []
            if collections.isEmpty {
                if engine?.isRefreshing ?? true {
                    LoadingLampView(text: "Reading the day…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    Text(engine?.lastError ?? "No shelves right now — pull the refresh arrow to try again.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            ForEach(collections) { collection in
                NavigationLink(value: collection) {
                    SmartCollectionCard(collection: collection)
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            if engine == nil { engine = SmartCollectionEngine(env: env) }
            await engine?.refreshIfNeeded()
        }
    }

    private var subtitle: String {
        guard let generated = engine?.lastGeneratedSummary else {
            return "Built from the hour, the calendar, and what you've been playing."
        }
        return generated
    }
}

// MARK: - Shelf strip (Home)

/// Compact horizontal version of the same shelves, for the Home feed.
struct SmartShelfStrip: View {
    @Environment(AppEnvironment.self) private var env
    @State private var engine: SmartCollectionEngine?

    var body: some View {
        let collections = engine?.collections ?? []
        VStack(alignment: .leading, spacing: 10) {
            if !collections.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.accent)
                    Text("Shelves For Right Now").sectionHeaderStyle()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(collections) { collection in
                            NavigationLink(value: collection) {
                                SmartCollectionMiniCard(collection: collection)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task {
            if engine == nil { engine = SmartCollectionEngine(env: env) }
            await engine?.refreshIfNeeded()
        }
    }
}

// MARK: - Cards

struct SmartCollectionCard: View {
    let collection: SmartCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: collection.iconName)
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
                Text(collection.badge)
                    .font(Theme.mono(10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("\(collection.items.count)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
            }

            Text(collection.title)
                .font(Theme.display(24))
                .foregroundStyle(Theme.textPrimary)

            Text(collection.blurb)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)

            HStack(spacing: 6) {
                ForEach(collection.items.prefix(3)) { item in
                    Text(LocalKnowledgeAI.prettyDate(item.date))
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.surface))
                }
                if collection.items.count > 3 {
                    Text("+\(collection.items.count - 3)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(raised: true)
    }
}

/// Compact variant for the Home shelf.
struct SmartCollectionMiniCard: View {
    let collection: SmartCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: collection.iconName)
                .font(.title3)
                .foregroundStyle(Theme.accent)
            Text(collection.badge)
                .font(Theme.mono(9, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            Text(collection.title)
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2, reservesSpace: true)
            Spacer(minLength: 0)
            Text("\(collection.items.count) shows")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .frame(width: 165, height: 160, alignment: .leading)
        .cardStyle(raised: true)
    }
}

// MARK: - Detail

struct SmartCollectionDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    let collection: SmartCollection

    @State private var engine: SmartCollectionEngine?
    @State private var pinState: PinState = .idle

    private enum PinState: Equatable {
        case idle, saving, saved(String)
    }

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    pinButton
                    ForEach(collection.items) { item in
                        itemLink(item)
                    }
                    footer
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if engine == nil { engine = SmartCollectionEngine(env: env) } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: collection.iconName)
                    .foregroundStyle(Theme.accent)
                Text(collection.badge)
                    .font(Theme.mono(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(Theme.accent)
            }
            Text(collection.title)
                .font(Theme.display(32))
                .foregroundStyle(Theme.textPrimary)
            Text(collection.blurb)
                .font(.system(.body, design: .serif).italic())
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var pinButton: some View {
        switch pinState {
        case .idle:
            Button {
                pinState = .saving
                Task {
                    let saved = await engine?.pinToLibrary(collection)
                    pinState = .saved(saved?.name ?? collection.title)
                }
            } label: {
                Label("Keep this shelf", systemImage: "tray.and.arrow.down.fill")
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().strokeBorder(Theme.accent.opacity(0.5)))
            }
            .buttonStyle(.plain)
        case .saving:
            HStack(spacing: 8) {
                ProgressView().tint(Theme.accent)
                Text("Finding the best tapes…")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textSecondary)
            }
        case .saved(let name):
            Label("Saved to Collections as “\(name)”", systemImage: "checkmark.circle.fill")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.sage)
        }
    }

    @ViewBuilder
    private func itemLink(_ item: SmartCollectionItem) -> some View {
        // A resolved identifier goes straight to the show; a bare date routes
        // through the resolver, which finds the best surviving tape.
        if let identifier = item.identifier {
            NavigationLink(value: showStub(for: item, identifier: identifier)) {
                itemRow(item)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: notableStub(for: item)) {
                itemRow(item)
            }
            .buttonStyle(.plain)
        }
    }

    private func itemRow(_ item: SmartCollectionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(item.note)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var footer: some View {
        Text("Curated by \(collection.curatedBy) · \(collection.generatedAt.formatted(.relative(presentation: .named)))")
            .font(Theme.mono(10))
            .foregroundStyle(Theme.textTertiary)
            .padding(.top, 4)
    }

    private func showStub(for item: SmartCollectionItem, identifier: String) -> Show {
        Show(identifier: identifier, title: item.title, date: IADates.parse(item.date),
             dateString: item.date, venue: item.title, location: nil,
             year: Int(item.date.prefix(4)), avgRating: nil, numReviews: nil,
             downloads: nil, source: nil)
    }

    /// The resolver only needs the date; the rest is display sugar.
    private func notableStub(for item: SmartCollectionItem) -> NotableShow {
        env.knowledgeBase.notableShow(on: item.date)
            ?? NotableShow(date: item.date, venue: item.title, location: item.subtitle,
                           eraID: "", tags: [], blurb: item.note, standoutSongs: [],
                           preferredIdentifier: nil)
    }
}
