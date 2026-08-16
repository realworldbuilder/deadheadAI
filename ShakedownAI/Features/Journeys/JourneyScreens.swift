import SwiftUI

// MARK: - Journey list

struct JourneysScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var refreshToken = 0

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("LONG STRANGE TRIP")
                        .font(Theme.mono(11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .tracking(2)
                    Text("Guided listening courses, taught by the archive itself. One show at a time, with context, focus tracks, and a place to write.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)

                    let _ = refreshToken
                    ForEach(env.knowledgeBase.journeys) { journey in
                        NavigationLink(value: journey) {
                            JourneyCard(journey: journey, progress: env.journeys.progress(for: journey))
                        }
                        .buttonStyle(.plain)
                    }
                    if env.knowledgeBase.journeys.isEmpty {
                        LoadingLampView(text: "Journeys load with the knowledge base.")
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle("Journeys")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: Journey.self) { journey in
            JourneyDetailScreen(journey: journey)
        }
        .onAppear { refreshToken += 1 }
    }
}

private struct JourneyCard: View {
    let journey: Journey
    let progress: (completed: Int, total: Int, isStarted: Bool, isFinished: Bool)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(journey.title)
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if progress.isFinished {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.sage)
                }
            }
            Text(journey.subtitle)
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surfaceRaised)
                        Capsule()
                            .fill(Theme.accentGradient)
                            .frame(width: progress.total > 0
                                   ? geo.size.width * CGFloat(progress.completed) / CGFloat(progress.total)
                                   : 0)
                    }
                }
                .frame(height: 7)
                Text(progress.isStarted ? "\(progress.completed)/\(progress.total)" : "\(progress.total) nights")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(raised: true)
    }
}

// MARK: - Journey detail

struct JourneyDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    let journey: Journey
    @State private var refreshToken = 0

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(journey.subtitle)
                        .font(.system(.callout, design: .serif).italic())
                        .foregroundStyle(Theme.textSecondary)

                    let _ = refreshToken
                    let state = env.journeys.state(for: journey.id)
                    let completed = Set(state?.completedDayIndices ?? [])

                    if state == nil {
                        Button {
                            env.journeys.start(journeyID: journey.id)
                            refreshToken += 1
                        } label: {
                            HStack {
                                Image(systemName: "figure.walk")
                                Text("Begin the Journey")
                                    .font(Theme.mono(14, weight: .bold))
                            }
                            .foregroundStyle(Color.black.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.accentGradient))
                        }
                    }

                    ForEach(Array(journey.days.enumerated()), id: \.offset) { index, day in
                        let unlocked = state != nil && (index == 0 || completed.contains(index - 1) || completed.contains(index))
                        NavigationLink(value: JourneyDayRoute(journey: journey, dayIndex: index)) {
                            dayRow(index: index, day: day,
                                   done: completed.contains(index),
                                   unlocked: unlocked)
                        }
                        .buttonStyle(.plain)
                        .disabled(!unlocked)
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle(journey.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: JourneyDayRoute.self) { route in
            JourneyDayScreen(journey: route.journey, dayIndex: route.dayIndex)
        }
        .onAppear { refreshToken += 1 }
    }

    private func dayRow(index: Int, day: Journey.JourneyDay, done: Bool, unlocked: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Theme.sage.opacity(0.2) : Theme.surfaceRaised)
                    .frame(width: 34, height: 34)
                if done {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.sage)
                } else if unlocked {
                    Text("\(index + 1)")
                        .font(Theme.mono(13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(day.title)
                    .font(Theme.headline)
                    .foregroundStyle(unlocked ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                Text(LocalKnowledgeAI.prettyDate(day.showDate))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .cardStyle()
        .opacity(unlocked ? 1 : 0.6)
    }
}

nonisolated struct JourneyDayRoute: Hashable {
    let journey: Journey
    let dayIndex: Int
}

// MARK: - Journey day

struct JourneyDayScreen: View {
    @Environment(AppEnvironment.self) private var env
    let journey: Journey
    let dayIndex: Int
    @State private var resolvedShow: Show?
    @State private var showingJournal = false
    @State private var refreshToken = 0

    private var day: Journey.JourneyDay { journey.days[dayIndex] }

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NIGHT \(dayIndex + 1) OF \(journey.days.count)")
                            .font(Theme.mono(10, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .tracking(1.5)
                        Text(day.title)
                            .font(Theme.display(26))
                            .foregroundStyle(Theme.textPrimary)
                        Text(LocalKnowledgeAI.prettyDate(day.showDate))
                            .font(Theme.mono(13))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Text(day.essay)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(4)

                    if let resolvedShow {
                        NavigationLink(value: resolvedShow) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Tonight's tape")
                                        .font(Theme.mono(10, weight: .bold))
                                        .foregroundStyle(Theme.textTertiary)
                                    Text(resolvedShow.displayVenue)
                                        .font(Theme.headline)
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(14)
                            .cardStyle(raised: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        LoadingLampView(text: "Finding tonight's tape…")
                    }

                    if !day.focusTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Listen for").sectionHeaderStyle()
                            ForEach(day.focusTracks, id: \.self) { track in
                                HStack(spacing: 8) {
                                    Image(systemName: "waveform")
                                        .font(.caption)
                                        .foregroundStyle(Theme.accent)
                                    Text(track)
                                        .font(Theme.body)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tonight's prompt").sectionHeaderStyle()
                        Text(day.journalPrompt)
                            .font(.system(.callout, design: .serif).italic())
                            .foregroundStyle(Theme.textSecondary)
                        Button {
                            showingJournal = true
                        } label: {
                            Label("Write about it", systemImage: "book.closed")
                                .font(Theme.mono(13, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(Theme.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    completeButton
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            resolvedShow = (try? await env.recordingProvider.recordings(forDate: day.showDate))?.first
        }
        .sheet(isPresented: $showingJournal) {
            if let resolvedShow {
                JournalEditorSheet(show: resolvedShow)
            }
        }
    }

    private var completeButton: some View {
        let _ = refreshToken
        let done = env.journeys.state(for: journey.id)?.completedDayIndices.contains(dayIndex) ?? false
        return Button {
            env.journeys.completeDay(journeyID: journey.id, dayIndex: dayIndex, totalDays: journey.days.count)
            refreshToken += 1
        } label: {
            HStack {
                Image(systemName: done ? "checkmark.seal.fill" : "checkmark.circle")
                Text(done ? "Night complete" : "Mark tonight complete")
                    .font(Theme.mono(14, weight: .bold))
            }
            .foregroundStyle(done ? Theme.sage : Color.black.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(done ? AnyShapeStyle(Theme.sage.opacity(0.15)) : AnyShapeStyle(Theme.accentGradient))
            )
        }
        .disabled(done)
    }
}
