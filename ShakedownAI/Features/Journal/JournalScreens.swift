import SwiftUI

// MARK: - Journal list

struct JournalListScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var refreshToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
                ForEach(Array(entries.enumerated()), id: \.element.persistentModelID) { index, entry in
                    JournalEntryCard(entry: entry, divider: index < entries.count - 1) {
                        env.library.deleteJournalEntry(entry)
                        refreshToken += 1
                    }
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .withMiniPlayer()
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !env.library.journalEntries.isEmpty {
                ShareLink(item: env.library.journalMarkdown(),
                          preview: SharePreview("TapeTree Journal")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export journal")
            }
        }
    }
}

struct JournalEntryCard: View {
    let entry: JournalEntry
    var divider = true
    var onDelete: (() -> Void)?
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.showDisplayName)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(entry.createdAt.formatted(date: .long, time: .omitted))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                if let mood = entry.mood, !mood.isEmpty {
                    TagPill(text: mood, tint: Theme.rose)
                }
                if onDelete != nil {
                    Menu {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Theme.textTertiary)
                            .padding(6)
                    }
                    .accessibilityLabel("Entry options")
                }
            }
            Text(entry.body)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
        }
        .listRowStyle(divider: divider)
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("There's no undo — the memory goes with it.")
        }
        .sensoryFeedback(.warning, trigger: confirmingDelete) { !$0 && $1 }
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
            VStack(alignment: .leading, spacing: 14) {
                Text(show.shortName)
                    .font(Theme.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                TextEditor(text: $text)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 180)
                    .cardStyle()
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Where were you? Who were you with? What did it do to you?")
                                .font(Theme.body)
                                .foregroundStyle(Theme.textTertiary)
                                .padding(18)
                                .allowsHitTesting(false)
                        }
                    }

                Text("Mood")
                    .eyebrowStyle()
                FlowLayout(spacing: 8) {
                    ForEach(Self.moods, id: \.self) { candidate in
                        Button {
                            mood = (mood == candidate) ? "" : candidate
                        } label: {
                            Text(candidate)
                                .font(Theme.subheadline)
                                .foregroundStyle(mood == candidate ? Theme.onAccent : Theme.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(mood == candidate ? Theme.accent : Color.clear)
                                )
                                .overlay(
                                    Capsule().strokeBorder(mood == candidate ? Color.clear : Theme.stroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(Theme.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
                ForEach(Array(events.enumerated()), id: \.element.persistentModelID) { index, event in
                    HStack(spacing: 12) {
                        Image(systemName: event.completed ? "checkmark.circle.fill" : "waveform")
                            .foregroundStyle(event.completed ? Theme.sage : Theme.textSecondary)
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
                                .font(.caption2)
                            Text("\(Int(event.secondsListened / 60))m \(Int(event.secondsListened.truncatingRemainder(dividingBy: 60)))s")
                                .font(.caption2)
                        }
                        .foregroundStyle(Theme.textTertiary)
                    }
                    .listRowStyle(divider: index < events.count - 1)
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .withMiniPlayer()
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Taste profile

struct TasteProfileScreen: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
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
        .background(Theme.background)
        .withMiniPlayer()
        .navigationTitle("Taste Profile")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { env.history.recomputeTasteProfile() }
    }

    private func statHeader(_ taste: TasteSnapshot) -> some View {
        HStack(spacing: 10) {
            stat(value: "\(Int(taste.totalSeconds / 3600))h", label: "In the archive")
            stat(value: "\(taste.showsHeard)", label: "Shows heard")
            stat(value: "\(taste.exploredYears.count)", label: "Years explored")
        }
        .listRowStyle()
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.title)
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func eraChart(_ taste: TasteSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Eras").sectionHeaderStyle()
            VStack(spacing: 10) {
                ForEach(env.knowledgeBase.eras) { era in
                    let weight = taste.eraWeights[era.id] ?? 0
                    HStack(spacing: 10) {
                        Text(era.years)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 74, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.stroke)
                                Capsule()
                                    .fill(Theme.accent)
                                    .frame(width: max(geo.size.width * weight, weight > 0 ? 4 : 0))
                            }
                            .animation(.snappy, value: weight)
                        }
                        .frame(height: 4)
                        Text(weight > 0 ? "\(Int(weight * 100))%" : "—")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func listBlock(title: String, items: [String]) -> some View {
        let visible = Array(items.prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionHeaderStyle()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(Theme.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 20)
                        Text(item)
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .listRowStyle(divider: index < visible.count - 1)
                }
            }
        }
    }
}
