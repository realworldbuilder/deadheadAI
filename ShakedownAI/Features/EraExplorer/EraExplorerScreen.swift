import SwiftUI

/// Interactive timeline, 1965 → 1995.
struct EraExplorerScreen: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Thirty years, seven bands wearing the same name.")
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
            .withMiniPlayer()
        }
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
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.accentGradient)
                            .frame(width: CGFloat(era.endYear - era.startYear + 1) * 14, height: 8)
                            .opacity(0.85)
                        Text("’\(String(era.startYear).suffix(2))")
                            .font(Theme.mono(10))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(era.years)
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(era.name)
                .font(Theme.display(24))
                .foregroundStyle(Theme.textPrimary)
            Text(era.style)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(raised: true)
    }
}

struct EraDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    let era: EraInfo

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    infoBlock(title: "The Sound", text: era.style)
                    infoBlock(title: "The Story", text: era.summary)
                    infoBlock(title: "Context", text: era.context)
                    infoBlock(title: "On Stage", text: era.lineup)

                    if !beginnerShows.isEmpty {
                        shelf(title: "Start Here", shows: beginnerShows)
                    }
                    if !mustHear.isEmpty {
                        shelf(title: "Must-Hear Nights", shows: mustHear)
                    }
                    if !eraShows.isEmpty {
                        shelf(title: "Deeper In", shows: eraShows)
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle(era.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(era.years)
                .font(Theme.mono(15, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(era.name)
                .font(Theme.display(30))
                .foregroundStyle(Theme.textPrimary)
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
            Text(title.uppercased())
                .font(Theme.mono(10, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .tracking(1.5)
            Text(text)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
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
