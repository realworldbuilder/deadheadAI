import SwiftUI

/// One year of the catalog, month by month: a strip of the months the band
/// played to jump by, then every night in order under its month heading.
/// Built for the listener who already knows the date they're after.
struct YearScreen: View {
    let year: Int
    let count: Int

    @Environment(AppEnvironment.self) private var env
    @State private var months: [MonthBucket] = []
    @State private var loaded = false

    /// The shows of one calendar month, in date order. Months the band
    /// didn't play (or left no playable tape) never become a bucket.
    nonisolated struct MonthBucket: Identifiable, Hashable, Sendable {
        let month: Int          // 1…12
        let shows: [Show]

        var id: Int { month }
        /// "September"
        var name: String { Self.symbols[month - 1] }
        /// "Sep"
        var shortName: String { Self.shortSymbols[month - 1] }

        private static let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_US_POSIX")
            return calendar
        }()
        private static let symbols = calendar.monthSymbols
        private static let shortSymbols = calendar.shortMonthSymbols
    }

    /// Pure grouping, kept off the view so it can be unit-tested. Rows are
    /// ordered by date, then show ID, so an early show precedes its late one.
    nonisolated static func monthBuckets(_ shows: [CatalogShow]) -> [MonthBucket] {
        Dictionary(grouping: shows, by: \.month)
            .sorted { $0.key < $1.key }
            .compactMap { month, rows in
                let playable = rows
                    .sorted { ($0.date, $0.showID) < ($1.date, $1.showID) }
                    .compactMap(\.asShow)
                return playable.isEmpty ? nil : MonthBucket(month: month, shows: playable)
            }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !env.catalog.isAvailable {
                        ErrorCard(message: "The show catalog isn't bundled in this build — browsing needs it.", retry: nil)
                    } else if !loaded {
                        LoadingLampView(text: "Opening \(year)…")
                    } else if months.isEmpty {
                        Text("Nothing surfaced. The vault is deep — try another angle.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 30)
                    } else {
                        Text("\(count) \(count == 1 ? "show" : "shows"), in order — best tape of each night.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                        monthStrip(proxy)
                        sections
                    }
                }
                .padding(Theme.screenPadding)
            }
        }
        .background(Theme.background)
        .withMiniPlayer()
        .navigationTitle(String(year))
        .navigationBarTitleDisplayMode(.large)
        .task {
            guard !loaded, env.catalog.isAvailable else { return }
            months = Self.monthBuckets(await env.catalog.shows(inYear: year))
            loaded = true
        }
    }

    /// Jump chips, one per month the band played that year.
    private func monthStrip(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(months) { bucket in
                    Button(bucket.shortName) {
                        withAnimation(.easeInOut) {
                            proxy.scrollTo(bucket.id, anchor: .top)
                        }
                    }
                    .buttonStyle(.chip)
                    .accessibilityLabel("Jump to \(bucket.name)")
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, -Theme.screenPadding)
        .contentMargins(.horizontal, Theme.screenPadding, for: .scrollContent)
    }

    private var sections: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(months) { bucket in
                Section {
                    ForEach(Array(bucket.shows.enumerated()), id: \.element.id) { index, show in
                        NavigationLink(value: show) {
                            ShowRow(show: show, divider: index < bucket.shows.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(bucket.name)
                        .eyebrowStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                        .background(Theme.background)
                        .id(bucket.id)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        YearScreen(year: 1977, count: 60)
    }
    .environment(AppEnvironment.mock())
}
