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
        let visible = songs
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, song in
                    NavigationLink(value: song) {
                        SongRow(song: song, divider: index < visible.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .withMiniPlayer()
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
    var divider = true

    var body: some View {
        HStack(spacing: 12) {
            // The song's face is its defining night's scan.
            if let date = song.famousVersions.first?.date {
                DateCover(date: date)
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.surfaceRaised))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    if let times = song.timesPlayed {
                        Text("\(times) plays")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(song.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
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

struct SongDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    let song: SongInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statsRow
                infoBlock(title: "How It Changed", text: song.evolution)

                if !song.famousVersions.isEmpty {
                    famousVersionsSection
                }
                if !seguePartnerSongs.isEmpty {
                    seguesSection
                }
                if !performances.isEmpty {
                    performancesSection
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .withMiniPlayer()
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard env.catalog.isAvailable, performances.isEmpty else { return }
            let key = Track.normalizeSongKey(song.title)
            let canonical = await env.catalog.songAliases()[key] ?? key
            performances = await env.catalog.performances(ofSong: canonical)
        }
    }

    @State private var performances: [CatalogShow] = []
    @State private var showAllPerformances = false

    /// Every night the catalog's setlists have this song — the full trail,
    /// not just the canon.
    private var performancesSection: some View {
        let visible = Array(performances.prefix(showAllPerformances ? performances.count : 8))
        return VStack(alignment: .leading, spacing: 8) {
            Text("All \(performances.count) Times They Played It").sectionHeaderStyle()
            Text("Every setlist it turns up in, first to last.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            VStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, night in
                    if let show = night.asShow {
                        NavigationLink(value: show) {
                            HStack {
                                Text(show.displayDate)
                                    .font(Theme.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(night.venue ?? "")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .listRowStyle(divider: index < visible.count - 1)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if performances.count > 8 {
                Button(showAllPerformances ? "Show fewer" : "Show all \(performances.count)") {
                    withAnimation(.snappy) { showAllPerformances.toggle() }
                }
                .buttonStyle(.secondary)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.title)
                .font(Theme.largeTitle)
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
                statCell(label: "Debut", value: LocalKnowledgeAI.prettyDate(debut))
            }
            if let last = song.lastPlayed {
                statCell(label: "Last", value: LocalKnowledgeAI.prettyDate(last))
            }
            if let times = song.timesPlayed {
                statCell(label: "Played", value: "\(times)×")
            }
        }
        .listRowStyle()
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .eyebrowStyle()
            Text(value)
                .font(Theme.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var famousVersionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Favorite Versions").sectionHeaderStyle()
            VStack(spacing: 0) {
                ForEach(Array(song.famousVersions.enumerated()), id: \.element.date) { index, version in
                    famousVersionCard(version, divider: index < song.famousVersions.count - 1)
                }
            }
        }
    }

    private func famousVersionCard(_ version: SongInfo.FamousVersion, divider: Bool) -> some View {
        Group {
            if let notable = resolvedNotable(version.date) {
                NavigationLink(value: notable) {
                    versionContent(version, divider: divider)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: placeholderNotable(for: version)) {
                    versionContent(version, divider: divider)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func versionContent(_ version: SongInfo.FamousVersion, divider: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            DateCover(date: version.date, venue: resolvedNotable(version.date)?.venue)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(LocalKnowledgeAI.prettyDate(version.date))
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)
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
        }
        .listRowStyle(divider: divider)
        .contentShape(Rectangle())
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
            Text("Goes Into").sectionHeaderStyle()
            Text("What it usually segues into, and out of.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            FlowLayout(spacing: 8) {
                ForEach(seguePartnerSongs) { partner in
                    NavigationLink(value: partner) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.caption2)
                            Text(partner.title)
                                .font(Theme.subheadline)
                        }
                        .foregroundStyle(Theme.denim)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(Capsule().strokeBorder(Theme.denim.opacity(0.5), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
}
