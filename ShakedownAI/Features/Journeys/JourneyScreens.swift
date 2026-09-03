import SwiftUI

// MARK: - Journey list

struct JourneysScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var refreshToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Long strange trip")
                    .eyebrowStyle()
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

                if !env.knowledgeBase.runs.isEmpty {
                    epicRunsSection
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .withMiniPlayer()
        .navigationTitle("Journeys")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: Journey.self) { journey in
            JourneyDetailScreen(journey: journey)
        }
        .navigationDestination(for: FamousRun.self) { run in
            FamousRunShowScreen(run: run)
        }
        .onAppear { refreshToken += 1 }
    }

    /// The canon of runs — single sequences inside one night that fans measure
    /// everything else against. Each row opens the show whose tape holds it.
    private var epicRunsSection: some View {
        let runs = env.knowledgeBase.runs.sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Epic runs")
                .eyebrowStyle()
                .padding(.top, 10)
            Text("Not whole shows — the sequences inside them that people never stop talking about.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
            VStack(spacing: 0) {
                ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                    NavigationLink(value: run) {
                        HStack(spacing: 12) {
                            Image(systemName: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.title)
                                    .font(Theme.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text(LocalKnowledgeAI.prettyDate(run.date))
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .listRowStyle(divider: index < runs.count - 1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Resolves the best tape for a famous run's date, then hands off to the
/// regular show page — where the run card is waiting with a play button.
struct FamousRunShowScreen: View {
    @Environment(AppEnvironment.self) private var env
    let run: FamousRun
    @State private var resolvedShow: Show?
    @State private var failed = false

    var body: some View {
        Group {
            if let resolvedShow {
                ShowDetailScreen(show: resolvedShow)
            } else if failed {
                ErrorCard(message: "Couldn't reach the archive for this night's tape. Check your connection and try again.") {
                    failed = false
                    Task { await resolve() }
                }
                .padding(Theme.screenPadding)
            } else {
                LoadingLampView(text: "Finding the tape with this run…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .task { await resolve() }
    }

    private func resolve() async {
        guard resolvedShow == nil else { return }
        resolvedShow = (try? await env.recordingProvider.recordings(forDate: run.date))?.first
        failed = resolvedShow == nil
    }
}

private struct JourneyCard: View {
    let journey: Journey
    let progress: (completed: Int, total: Int, isStarted: Bool, isFinished: Bool)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(journey.title)
                    .font(Theme.title)
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
                        Capsule().fill(Theme.stroke)
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: progress.total > 0
                                   ? geo.size.width * CGFloat(progress.completed) / CGFloat(progress.total)
                                   : 0)
                    }
                    .animation(.snappy, value: progress.completed)
                }
                .frame(height: 4)
                Text(progress.isStarted ? "\(progress.completed)/\(progress.total)" : "\(progress.total) nights")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - Journey detail

struct JourneyDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    let journey: Journey
    @State private var refreshToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(journey.subtitle)
                    .font(.callout)
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
                        }
                    }
                    .buttonStyle(.primary(fullWidth: true))
                }

                VStack(spacing: 0) {
                    ForEach(Array(journey.days.enumerated()), id: \.offset) { index, day in
                        let unlocked = state != nil && (index == 0 || completed.contains(index - 1) || completed.contains(index))
                        NavigationLink(value: JourneyDayRoute(journey: journey, dayIndex: index)) {
                            dayRow(index: index, day: day,
                                   done: completed.contains(index),
                                   unlocked: unlocked,
                                   divider: index < journey.days.count - 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(!unlocked)
                    }
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .withMiniPlayer()
        .navigationTitle(journey.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: JourneyDayRoute.self) { route in
            JourneyDayScreen(journey: route.journey, dayIndex: route.dayIndex)
        }
        .onAppear { refreshToken += 1 }
    }

    private func dayRow(index: Int, day: Journey.JourneyDay, done: Bool, unlocked: Bool, divider: Bool) -> some View {
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
                        .font(Theme.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
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
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .listRowStyle(divider: divider)
        .contentShape(Rectangle())
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
    @Environment(PlayerEngine.self) private var engine
    let journey: Journey
    let dayIndex: Int
    @State private var resolvedShow: Show?
    @State private var showingJournal = false
    @State private var refreshToken = 0
    @State private var isStartingRun = false
    @State private var runUnavailable = false

    private var day: Journey.JourneyDay { journey.days[dayIndex] }
    private var focusRun: FamousRun? { day.focusRunID.flatMap(env.knowledgeBase.run(id:)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Night \(dayIndex + 1) of \(journey.days.count)")
                        .eyebrowStyle()
                    Text(day.title)
                        .font(Theme.largeTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(LocalKnowledgeAI.prettyDate(day.showDate))
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                Text(day.essay)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(4)

                if let resolvedShow {
                    NavigationLink(value: resolvedShow) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tonight's tape")
                                    .font(Theme.caption)
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
                        .contentShape(Rectangle())
                        .cardStyle()
                    }
                    .buttonStyle(.plain)
                } else {
                    LoadingLampView(text: "Finding tonight's tape…")
                }

                if let run = focusRun {
                    runCard(run)
                }

                if !day.focusTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Listen for").sectionHeaderStyle()
                        ForEach(day.focusTracks, id: \.self) { track in
                            HStack(spacing: 8) {
                                Image(systemName: "waveform")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
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
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                    Button {
                        showingJournal = true
                    } label: {
                        Label("Write about it", systemImage: "book.closed")
                            .font(Theme.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                completeButton
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .withMiniPlayer()
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: refreshToken)
        .task {
            resolvedShow = (try? await env.recordingProvider.recordings(forDate: day.showDate))?.first
        }
        .sheet(isPresented: $showingJournal) {
            if let resolvedShow {
                JournalEditorSheet(show: resolvedShow)
            }
        }
    }

    /// Tonight's headline sequence, playable without leaving the journey.
    private func runCard(_ run: FamousRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text("The famous run")
                    .eyebrowStyle()
            }
            Text(run.title)
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(run.blurb)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if runUnavailable {
                Text("This tape splits the run differently — open tonight's tape to explore it.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Button {
                    Task { await playRun(run) }
                } label: {
                    HStack(spacing: 6) {
                        if isStartingRun {
                            ProgressView().tint(Theme.textSecondary).scaleEffect(0.7)
                        } else {
                            Image(systemName: "play.circle.fill")
                        }
                        Text("Play the run")
                            .font(Theme.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
                .disabled(isStartingRun || resolvedShow == nil)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func playRun(_ run: FamousRun) async {
        guard let show = resolvedShow, !isStartingRun else { return }
        isStartingRun = true
        defer { isStartingRun = false }
        guard let detail = try? await env.metadataProvider.detail(for: show.identifier),
              let range = RunResolver.resolve(run, in: detail.tracks) else {
            runUnavailable = true
            return
        }
        engine.play(show: show, tracks: detail.tracks, startAt: range.lowerBound)
        engine.isPresentingFullPlayer = true
    }

    @ViewBuilder
    private var completeButton: some View {
        let _ = refreshToken
        let done = env.journeys.state(for: journey.id)?.completedDayIndices.contains(dayIndex) ?? false
        if done {
            Button {
                env.journeys.completeDay(journeyID: journey.id, dayIndex: dayIndex, totalDays: journey.days.count)
                refreshToken += 1
            } label: {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Night complete")
                }
                .foregroundStyle(Theme.sage)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondary)
            .disabled(true)
        } else {
            Button {
                env.journeys.completeDay(journeyID: journey.id, dayIndex: dayIndex, totalDays: journey.days.count)
                refreshToken += 1
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle")
                    Text("Mark tonight complete")
                }
            }
            .buttonStyle(.primary(fullWidth: true))
        }
    }
}
