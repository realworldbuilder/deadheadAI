import SwiftUI

/// The Vault: browse the whole catalog by year and venue — every show the
/// band played, straight from the bundled catalog, no network.
struct BrowseScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var yearCounts: [(year: Int, count: Int)] = []
    @State private var venues: [VenueSummary] = []
    @State private var loaded = false

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 8)]

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !env.catalog.isAvailable {
                        ErrorCard(message: "The show catalog isn't bundled in this build — browsing needs it.", retry: nil)
                    } else if loaded {
                        yearSection
                        venueSection
                    } else {
                        LoadingLampView(text: "Opening the vault…")
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle("The Vault")
        .navigationBarTitleDisplayMode(.large)
        .task {
            guard !loaded, env.catalog.isAvailable else { return }
            yearCounts = await env.catalog.yearCounts()
            venues = await env.catalog.venues(matching: nil, limit: 15)
            loaded = true
        }
    }

    /// Years grouped under their era, so the grid reads as the band's life.
    private var yearSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(env.knowledgeBase.eras) { era in
                let years = yearCounts.filter { era.startYear <= $0.year && $0.year <= era.endYear }
                if !years.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(era.name.uppercased())
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(Theme.accent)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(years, id: \.year) { entry in
                                NavigationLink {
                                    ShowListScreen(
                                        title: String(entry.year),
                                        subtitle: "\(entry.count) shows, in order — best tape of each night.",
                                        loader: { await env.catalog.shows(inYear: entry.year).compactMap(\.asShow) }
                                    )
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(String(entry.year))
                                            .font(Theme.mono(15, weight: .bold))
                                            .foregroundStyle(Theme.textPrimary)
                                        Text("\(entry.count)")
                                            .font(Theme.mono(10))
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .cardStyle()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var venueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hallowed Ground").sectionHeaderStyle()
            Text("The rooms they kept coming back to.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            ForEach(venues) { venue in
                NavigationLink {
                    ShowListScreen(
                        title: venue.venue,
                        subtitle: venue.city.map { "\(venue.showCount) nights in \($0)." },
                        loader: { await env.catalog.shows(atVenue: venue.venue).compactMap(\.asShow) }
                    )
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(venue.venue)
                                .font(Theme.headline)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            if let city = venue.city {
                                Text(city)
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                        Text("\(venue.showCount)")
                            .font(Theme.mono(13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(12)
                    .cardStyle()
                }
                .buttonStyle(.plain)
            }
        }
    }
}
