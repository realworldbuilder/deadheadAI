import SwiftUI

struct SongExplorerScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var filter = ""

    private var songs: [SongInfo] {
        let all = env.knowledgeBase.songs.sorted { $0.title < $1.title }
        guard !filter.isEmpty else { return all }
        let needle = filter.lowercased()
        return all.filter { $0.title.lowercased().contains(needle) || $0.key.contains(needle) }
    }

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(songs) { song in
                        NavigationLink(value: song) {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $filter, prompt: "Find a song")
        .navigationDestination(for: SongInfo.self) { song in
            SongDetailScreen(song: song)
        }
    }
}

struct SongRow: View {
    let song: SongInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    if let times = song.timesPlayed {
                        Text("\(times) plays")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(song.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .cardStyle()
    }
}

struct SongDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    let song: SongInfo

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statsRow
                    infoBlock(title: "Evolution", text: song.evolution)

                    if !song.famousVersions.isEmpty {
                        famousVersionsSection
                    }
                    if !seguePartnerSongs.isEmpty {
                        seguesSection
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.title)
                .font(Theme.display(30))
                .foregroundStyle(Theme.textPrimary)
            if let writers = song.writtenBy {
                Text("Written by \(writers)")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                ForEach(song.tags, id: \.self) { TagPill(text: $0) }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            if let debut = song.debut {
                statCell(label: "DEBUT", value: LocalKnowledgeAI.prettyDate(debut))
            }
            if let last = song.lastPlayed {
                statCell(label: "LAST", value: LocalKnowledgeAI.prettyDate(last))
            }
            if let times = song.timesPlayed {
                statCell(label: "PLAYED", value: "\(times)×")
            }
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .tracking(1.2)
            Text(value)
                .font(Theme.mono(14, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardStyle()
    }

    private var famousVersionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The Versions That Matter").sectionHeaderStyle()
            ForEach(song.famousVersions, id: \.date) { version in
                famousVersionCard(version)
            }
        }
    }

    private func famousVersionCard(_ version: SongInfo.FamousVersion) -> some View {
        Group {
            if let notable = resolvedNotable(version.date) {
                NavigationLink(value: notable) {
                    versionContent(version)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: placeholderNotable(for: version)) {
                    versionContent(version)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func versionContent(_ version: SongInfo.FamousVersion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LocalKnowledgeAI.prettyDate(version.date))
                    .font(Theme.mono(15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                if let label = version.label {
                    TagPill(text: label, tint: Theme.rose)
                }
                Spacer()
                Image(systemName: "play.circle")
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(version.note)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(raised: true)
    }

    private func resolvedNotable(_ date: String) -> NotableShow? {
        env.knowledgeBase.notableShow(on: date)
    }

    /// Famous versions can point at dates outside the curated show list; the
    /// resolver screen finds the best archive tape for any date.
    private func placeholderNotable(for version: SongInfo.FamousVersion) -> NotableShow {
        NotableShow(date: version.date, venue: "The night of \(LocalKnowledgeAI.prettyDate(version.date))",
                    location: "", eraID: TasteEngine.eraID(forYear: Int(version.date.prefix(4)) ?? 1970),
                    tags: [], blurb: version.note, standoutSongs: [song.title], preferredIdentifier: nil)
    }

    private var seguePartnerSongs: [SongInfo] {
        song.seguePartners.compactMap(env.knowledgeBase.song(forKey:))
    }

    private var seguesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Runs With").sectionHeaderStyle()
            Text("The conversations this song usually joins.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            FlowLayout(spacing: 8) {
                ForEach(seguePartnerSongs) { partner in
                    NavigationLink(value: partner) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.caption2)
                            Text(partner.title)
                                .font(Theme.mono(12, weight: .medium))
                        }
                        .foregroundStyle(Theme.denim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.denim.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(Theme.denim.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
}
