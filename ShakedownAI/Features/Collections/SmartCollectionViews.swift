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
                        .foregroundStyle(Theme.textSecondary)
                }
                .disabled(engine?.isRefreshing ?? true)
                .accessibilityLabel("Refresh shelves")
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
                        .foregroundStyle(Theme.textSecondary)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: collection.iconName)
                    .font(.footnote)
                Text(collection.badge.sentenceCased)
                    .font(Theme.footnote.weight(.semibold))
                Spacer()
                Text("\(collection.items.count) shows")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(Theme.textSecondary)

            Text(collection.title)
                .font(Theme.title)
                .foregroundStyle(Theme.textPrimary)

            Text(collection.blurb)
                .font(Theme.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)

            // The shelf itself: the tapes, spine out.
            HStack(spacing: 6) {
                ForEach(collection.items.prefix(5)) { item in
                    ShowThumbnail(show: Self.thumbShow(item), size: 52)
                }
                if collection.items.count > 5 {
                    Text("+\(collection.items.count - 5)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.top, 2)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// A show just complete enough for the artwork chain to find its cover.
    static func thumbShow(_ item: SmartCollectionItem) -> Show {
        let venue = SmartCollectionMiniCard.venueOnly(item.title)
        return Show(identifier: item.identifier ?? "", title: venue, date: IADates.parse(item.date),
                    dateString: item.date, venue: venue, location: nil,
                    year: Int(item.date.prefix(4)), avgRating: nil, numReviews: nil,
                    downloads: nil, source: nil)
    }
}

/// Compact variant for the Home shelf: the first show's art on top, the
/// shelf's name beneath it.
struct SmartCollectionMiniCard: View {
    @Environment(AppEnvironment.self) private var env
    let collection: SmartCollection

    @State private var coverImage: UIImage?

    /// Item titles arrive as "5/26/72 — Lyceum Theatre"; the tile already
    /// sets the date, so keep only the venue.
    static func venueOnly(_ title: String) -> String {
        guard let range = title.range(of: " — ") else { return title }
        return String(title[range.upperBound...])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                } else if let first = collection.items.first {
                    ArtworkPlaceholder(date: LocalKnowledgeAI.prettyDate(first.date),
                                       venue: Self.venueOnly(first.title))
                } else {
                    ArtworkPlaceholder(venue: collection.title)
                }
            }
                .frame(width: 165, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
            HStack(spacing: 4) {
                Image(systemName: collection.iconName)
                    .font(.caption2)
                Text(collection.badge.sentenceCased)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.textSecondary)
            Text(collection.title)
                .font(Theme.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Text("\(collection.items.count) shows")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(width: 165, alignment: .leading)
        .task(id: collection.id) {
            for item in collection.items {
                if let found = await ArchiveArtwork.shared.cover(
                    date: item.date, identifier: item.identifier, catalog: env.catalog) {
                    coverImage = found
                    return
                }
            }
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                pinButton
                    .animation(.snappy, value: pinState)
                VStack(spacing: 0) {
                    ForEach(Array(collection.items.enumerated()), id: \.element.id) { index, item in
                        itemLink(item, divider: index < collection.items.count - 1)
                    }
                }
                footer
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .withMiniPlayer()
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if engine == nil { engine = SmartCollectionEngine(env: env) } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: collection.iconName)
                    .foregroundStyle(Theme.textSecondary)
                Text(collection.badge.sentenceCased)
                    .font(Theme.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(collection.title)
                .font(Theme.largeTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(collection.blurb)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var pinButton: some View {
        switch pinState {
        case .idle:
            Button {
                withAnimation(.snappy) { pinState = .saving }
                Task {
                    let saved = await engine?.pinToLibrary(collection)
                    withAnimation(.snappy) {
                        pinState = .saved(saved?.name ?? collection.title)
                    }
                }
            } label: {
                Label("Keep this shelf", systemImage: "tray.and.arrow.down.fill")
            }
            .buttonStyle(.primary)
        case .saving:
            HStack(spacing: 8) {
                ProgressView().tint(Theme.textSecondary)
                Text("Finding the best tapes…")
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 12)
        case .saved(let name):
            Label("Saved to Collections as “\(name)”", systemImage: "checkmark.circle.fill")
                .font(Theme.subheadline.weight(.medium))
                .foregroundStyle(Theme.sage)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func itemLink(_ item: SmartCollectionItem, divider: Bool) -> some View {
        // A resolved identifier goes straight to the show; a bare date routes
        // through the resolver, which finds the best surviving tape.
        if let identifier = item.identifier {
            NavigationLink(value: showStub(for: item, identifier: identifier)) {
                itemRow(item, divider: divider)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: notableStub(for: item)) {
                itemRow(item, divider: divider)
            }
            .buttonStyle(.plain)
        }
    }

    private func itemRow(_ item: SmartCollectionItem, divider: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ShowThumbnail(show: showStub(for: item, identifier: item.identifier ?? ""), size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(Theme.caption)
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
        .listRowStyle(divider: divider)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        Text("Curated by \(collection.curatedBy) · \(collection.generatedAt.formatted(.relative(presentation: .named)))")
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
            .padding(.top, 4)
    }

    private func showStub(for item: SmartCollectionItem, identifier: String) -> Show {
        let venue = SmartCollectionMiniCard.venueOnly(item.title)
        return Show(identifier: identifier, title: venue, date: IADates.parse(item.date),
             dateString: item.date, venue: venue, location: nil,
             year: Int(item.date.prefix(4)), avgRating: nil, numReviews: nil,
             downloads: nil, source: nil)
    }

    /// The resolver only needs the date; the rest is display sugar.
    private func notableStub(for item: SmartCollectionItem) -> NotableShow {
        env.knowledgeBase.notableShow(on: item.date)
            ?? NotableShow(date: item.date, venue: SmartCollectionMiniCard.venueOnly(item.title), location: item.subtitle,
                           eraID: "", tags: [], blurb: item.note, standoutSongs: [],
                           preferredIdentifier: nil)
    }
}

private extension String {
    /// "WHAT THE ARCHIVE LOVES" → "What the archive loves";
    /// "DEEP CUT · WEDNESDAY" → "Deep cut · Wednesday".
    var sentenceCased: String {
        components(separatedBy: " · ").map { part -> String in
            guard let first = part.first else { return part }
            return first.uppercased() + part.dropFirst().lowercased()
        }.joined(separator: " · ")
    }
}
