import SwiftUI

// MARK: - Journal list

struct JournalListScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var refreshToken = 0

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let _ = refreshToken
                    let entries = env.library.journalEntries
                    if entries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "book.closed")
                                .font(.largeTitle)
                                .foregroundStyle(Theme.textTertiary)
                            Text("Your journal is empty")
                                .font(Theme.title)
                                .foregroundStyle(Theme.textPrimary)
                            Text("\"Listened while driving through the Blue Ridge.\"\n\"This Morning Dew wrecked me.\"\n\nYears from now, these notes will take you back. Write from any show page.")
                                .font(Theme.body)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }
                    ForEach(entries, id: \.persistentModelID) { entry in
                        JournalEntryCard(entry: entry) {
                            env.library.deleteJournalEntry(entry)
                            refreshToken += 1
                        }
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !env.library.journalEntries.isEmpty {
                ShareLink(item: env.library.journalMarkdown(),
                          preview: SharePreview("Shakedown Journal")) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}

struct JournalEntryCard: View {
    let entry: JournalEntry
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.showDisplayName)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    Text(entry.createdAt.formatted(date: .long, time: .omitted))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                if let mood = entry.mood, !mood.isEmpty {
                    TagPill(text: mood, tint: Theme.rose)
                }
                if let onDelete {
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Theme.textTertiary)
                            .padding(6)
                    }
                }
            }
            Text(entry.body)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - Journal editor (opened from a show)

struct JournalEditorSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let show: Show
    @State private var text = ""
    @State private var mood = ""

    private static let moods = ["blissed", "wistful", "electric", "peaceful", "wrecked", "grateful"]

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBackground()
                VStack(alignment: .leading, spacing: 14) {
                    Text(show.shortName)
                        .font(Theme.mono(13, weight: .semibold))
                        .foregroundStyle(Theme.accent)

                    TextEditor(text: $text)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 180)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Where were you? Who were you with? What did it do to you?")
                                    .font(.system(.body, design: .serif).italic())
                                    .foregroundStyle(Theme.textTertiary)
                                    .padding(18)
                                    .allowsHitTesting(false)
                            }
                        }

                    Text("MOOD")
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                    FlowLayout(spacing: 8) {
                        ForEach(Self.moods, id: \.self) { candidate in
                            Button {
                                mood = (mood == candidate) ? "" : candidate
                            } label: {
                                Text(candidate)
                                    .font(Theme.mono(12, weight: .medium))
                                    .foregroundStyle(mood == candidate ? Color.black.opacity(0.8) : Theme.textSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(mood == candidate ? Theme.accent : Theme.surfaceRaised)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
                .padding(Theme.screenPadding)
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        env.library.addJournalEntry(show: show, body: text, mood: mood.isEmpty ? nil : mood)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - History

struct HistoryScreen: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let events = env.history.recentEvents(limit: 100)
                    if events.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "hourglass")
                                .font(.largeTitle)
                                .foregroundStyle(Theme.textTertiary)
                            Text("No listening yet — the archive awaits.")
                                .font(Theme.body)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }
                    ForEach(events, id: \.persistentModelID) { event in
                        HStack(spacing: 12) {
                            Image(systemName: event.completed ? "checkmark.circle.fill" : "waveform")
                                .foregroundStyle(event.completed ? Theme.sage : Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.trackTitle)
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text(event.showDisplayName)
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(event.startedAt.formatted(.relative(presentation: .named)))
                                    .font(Theme.mono(10))
                                Text("\(Int(event.secondsListened / 60))m \(Int(event.secondsListened.truncatingRemainder(dividingBy: 60)))s")
                                    .font(Theme.mono(10))
                            }
                            .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(11)
                        .cardStyle()
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Taste profile

struct TasteProfileScreen: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let taste = env.history.tasteSnapshot
                    if taste.totalSeconds < 60 {
                        VStack(spacing: 12) {
                            Image(systemName: "ear")
                                .font(.largeTitle)
                                .foregroundStyle(Theme.textTertiary)
                            Text("Still listening…")
                                .font(Theme.title)
                                .foregroundStyle(Theme.textPrimary)
                            Text("Play a few shows and the app starts learning your ears — favorite eras, songs, and rooms.")
                                .font(Theme.body)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        statHeader(taste)
                        if !taste.eraWeights.isEmpty {
                            eraChart(taste)
                        }
                        if !taste.topSongKeys.isEmpty {
                            listBlock(title: "Songs You Return To",
                                      items: taste.topSongKeys.map { env.knowledgeBase.song(forKey: $0)?.title ?? $0.capitalized })
                        }
                        if !taste.favoriteVenues.isEmpty {
                            listBlock(title: "Rooms You Haunt", items: taste.favoriteVenues)
                        }
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle("Taste Profile")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { env.history.recomputeTasteProfile() }
    }

    private func statHeader(_ taste: TasteSnapshot) -> some View {
        HStack(spacing: 10) {
            stat(value: "\(Int(taste.totalSeconds / 3600))h", label: "IN THE ARCHIVE")
            stat(value: "\(taste.showsHeard)", label: "SHOWS HEARD")
            stat(value: "\(taste.exploredYears.count)", label: "YEARS EXPLORED")
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.display(24))
                .foregroundStyle(Theme.accent)
            Text(label)
                .font(Theme.mono(9, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .cardStyle()
    }

    private func eraChart(_ taste: TasteSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Eras").sectionHeaderStyle()
            VStack(spacing: 8) {
                ForEach(env.knowledgeBase.eras) { era in
                    let weight = taste.eraWeights[era.id] ?? 0
                    HStack(spacing: 10) {
                        Text(era.years)
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 74, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.surfaceRaised)
                                Capsule()
                                    .fill(Theme.accentGradient)
                                    .frame(width: max(geo.size.width * weight, weight > 0 ? 6 : 0))
                            }
                        }
                        .frame(height: 10)
                        Text(weight > 0 ? "\(Int(weight * 100))%" : "—")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
            .padding(Theme.cardPadding)
            .cardStyle()
        }
    }

    private func listBlock(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionHeaderStyle()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 20)
                        Text(item)
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }
}
