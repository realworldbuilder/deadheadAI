import SwiftUI

/// Interactive timeline, 1965 → 1995.
struct EraExplorerScreen: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Thirty years, and a different band every few of them.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)

                timeline

                ForEach(env.knowledgeBase.eras) { era in
                    NavigationLink(value: era) {
                        EraCard(era: era)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .withMiniPlayer()
        .navigationTitle("Eras")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: EraInfo.self) { era in
            EraDetailScreen(era: era)
        }
    }

    private var timeline: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(env.knowledgeBase.eras) { era in
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: CGFloat(era.endYear - era.startYear + 1) * 14, height: 4)
                        Text("’\(String(era.startYear).suffix(2))")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.trailing, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct EraCard: View {
    let era: EraInfo

    /// The era's face: scans from its must-hear nights, beginner picks next.
    var coverDates: [String] { EraInfo.coverDates(for: era, limit: 3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverStrip(dates: coverDates, height: 88)
            HStack {
                Text(era.years)
                    .font(Theme.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(era.name)
                .font(Theme.title)
                .foregroundStyle(Theme.textPrimary)
            Text(era.style)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .cardStyle()
    }
}

struct EraDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    let era: EraInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                infoBlock(title: "The sound", text: era.style)
                infoBlock(title: "The story", text: era.summary)
                infoBlock(title: "Context", text: era.context)
                infoBlock(title: "Lineup", text: era.lineup)

                if !beginnerShows.isEmpty {
                    shelf(title: "Start Here", shows: beginnerShows)
                }
                if !mustHear.isEmpty {
                    shelf(title: "Must-Hear Shows", shows: mustHear)
                }
                if !eraShows.isEmpty {
                    shelf(title: "Deeper In", shows: eraShows)
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .withMiniPlayer()
        .navigationTitle(era.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The nights that define the era, each scan a door to its show.
            HStack(spacing: 6) {
                ForEach(EraInfo.coverDates(for: era, limit: 4), id: \.self) { date in
                    let cover = DateCover(date: date)
                        .frame(maxWidth: .infinity)
                        .frame(height: 118)
                    if let notable = env.knowledgeBase.notableShow(on: date) {
                        NavigationLink(value: notable) { cover }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(LocalKnowledgeAI.prettyDate(date)), \(notable.venue)")
                    } else {
                        cover
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(era.years)
                    .font(Theme.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(era.name)
                    .font(Theme.largeTitle)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }

    private var beginnerShows: [NotableShow] {
        era.beginnerShows.compactMap(env.knowledgeBase.notableShow(on:))
    }

    private var mustHear: [NotableShow] {
        era.mustHear.compactMap(env.knowledgeBase.notableShow(on:))
            .filter { show in !era.beginnerShows.contains(show.date) }
    }

    private var eraShows: [NotableShow] {
        env.knowledgeBase.shows(inEra: era.id)
            .filter { !era.beginnerShows.contains($0.date) && !era.mustHear.contains($0.date) }
    }

    private func infoBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .eyebrowStyle()
            Text(text)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shelf(title: String, shows: [NotableShow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionHeaderStyle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shows) { notable in
                        NavigationLink(value: notable) {
                            NotableShowCard(notable: notable, era: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

extension EraInfo {
    /// Dates whose scans stand for the era: must-hear nights first, then
    /// beginner picks, deduplicated, in the order the curator listed them.
    nonisolated static func coverDates(for era: EraInfo, limit: Int) -> [String] {
        var seen = Set<String>()
        return (era.mustHear + era.beginnerShows).filter { seen.insert($0).inserted }.prefix(limit).map { $0 }
    }
}
