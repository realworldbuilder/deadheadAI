import SwiftUI

@Observable
final class ShowDetailModel {
    var show: Show
    var detail: RecordingDetail?
    var otherRecordings: [Show] = []
    var guide: ShowGuide?
    var isLoadingGuide = false
    var errorMessage: String?
    var isLoading = false

    private let metadata: any MetadataProvider
    private let recordings: any LiveRecordingProvider
    private let ai: any AIProvider

    init(show: Show, metadata: any MetadataProvider, recordings: any LiveRecordingProvider,
         ai: any AIProvider) {
        self.show = show
        self.metadata = metadata
        self.recordings = recordings
        self.ai = ai
    }

    func loadGuide() async {
        guard guide == nil, let detail, !isLoadingGuide else { return }
        isLoadingGuide = true
        guide = try? await ai.showGuide(for: detail, show: show)
        isLoadingGuide = false
    }

    func load() async {
        guard detail == nil else { return }
        isLoading = true
        errorMessage = nil
        do {
            detail = try await metadata.detail(for: show.identifier)
            if let day = show.dateString {
                let all = try await recordings.recordings(forDate: day)
                otherRecordings = all.filter { $0.identifier != show.identifier }
            }
        } catch HTTPError.serviceUnavailable {
            errorMessage = ArchiveHealth.outageMessage
        } catch {
            errorMessage = "Couldn't reach the archive. Check your connection and try again."
        }
        isLoading = false
    }

    func switchSource(to other: Show) async {
        show = other
        detail = nil
        otherRecordings = []
        await load()
    }
}

struct ShowDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(PlayerEngine.self) private var engine
    @State private var model: ShowDetailModel?
    @State private var showingSources = false
    @State private var showingJournal = false
    @State private var showingCollectionPicker = false

    let show: Show

    var body: some View {
        ZStack {
            SpaceBackground()
            if let model {
                content(model)
            }
        }
        .task {
            if model == nil {
                model = ShowDetailModel(show: show,
                                        metadata: env.metadataProvider,
                                        recordings: env.recordingProvider,
                                        ai: env.aiProvider)
            }
            await model?.load()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingJournal = true
                } label: {
                    Image(systemName: "book.closed")
                }
                .accessibilityLabel("Write a journal entry")
                Button {
                    showingCollectionPicker = true
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .accessibilityLabel("Save to collection")
            }
        }
        .sheet(isPresented: $showingJournal) {
            JournalEditorSheet(show: model?.show ?? show)
        }
        .sheet(isPresented: $showingCollectionPicker) {
            CollectionPickerSheet(show: model?.show ?? show)
        }
    }

    @ViewBuilder
    private func content(_ model: ShowDetailModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(model)

                if model.isLoading && model.detail == nil {
                    LoadingLampView(text: "Tuning in from the archive…")
                } else if let error = model.errorMessage {
                    ErrorCard(message: error) {
                        Task { await model.load() }
                    }
                } else if let detail = model.detail {
                    playButton(model, detail: detail)
                    guideSection(model)
                    trackList(detail, model: model)
                    if !model.otherRecordings.isEmpty {
                        sourcesSection(model)
                    }
                    if let notes = detail.notes ?? detail.lineage {
                        notesSection(notes: detail.notes, lineage: detail.lineage, fallback: notes)
                    }
                    if !detail.reviews.isEmpty {
                        reviewsSection(detail)
                    }
                }
            }
            .padding(Theme.screenPadding)
        }
        .withMiniPlayer()
    }

    private func header(_ model: ShowDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.show.displayDate)
                .font(Theme.mono(15, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text(model.show.venue ?? model.show.title)
                .font(Theme.display(28))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let location = model.show.location {
                Text(location)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 8) {
                if model.show.isSoundboard { TagPill(text: "SOUNDBOARD", tint: Theme.sage) }
                if model.show.isMillerTransfer { TagPill(text: "MILLER", tint: Theme.denim) }
                if let rating = model.show.avgRating, rating > 0 {
                    RatingDots(rating: rating)
                }
                if let reviews = model.show.numReviews, reviews > 0 {
                    Text("\(reviews) reviews")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func playButton(_ model: ShowDetailModel, detail: RecordingDetail) -> some View {
        Button {
            engine.play(show: model.show, tracks: detail.tracks)
            engine.isPresentingFullPlayer = true
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text(detail.tracks.isEmpty ? "No streamable tracks" : "Play Show")
                    .font(Theme.mono(15, weight: .bold))
                Spacer()
                Text("\(detail.tracks.count) tracks")
                    .font(Theme.mono(12))
                    .opacity(0.75)
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.accentGradient)
            )
        }
        .disabled(detail.tracks.isEmpty)
    }

    @ViewBuilder
    private func guideSection(_ model: ShowDetailModel) -> some View {
        if let guide = model.guide {
            ShowGuideView(guide: guide)
        } else {
            Button {
                Task { await model.loadGuide() }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listening Guide")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Mood, history, transitions, and what to listen for.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if model.isLoadingGuide {
                        ProgressView().tint(Theme.accent)
                    } else {
                        Image(systemName: "chevron.down.circle")
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(14)
                .cardStyle(raised: true)
            }
            .buttonStyle(.plain)
            .disabled(model.isLoadingGuide)
        }
    }

    private func trackList(_ detail: RecordingDetail, model: ShowDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Setlist").sectionHeaderStyle()
            VStack(spacing: 0) {
                ForEach(Array(detail.tracks.enumerated()), id: \.element.id) { index, track in
                    Button {
                        engine.play(show: model.show, tracks: detail.tracks, startAt: index)
                    } label: {
                        HStack(spacing: 10) {
                            Text(String(format: "%02d", index + 1))
                                .font(Theme.mono(12))
                                .foregroundStyle(isCurrent(track, model) ? Theme.accent : Theme.textTertiary)
                            Text(track.title)
                                .font(Theme.body)
                                .foregroundStyle(isCurrent(track, model) ? Theme.accent : Theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(track.displayDuration)
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.vertical, 11)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < detail.tracks.count - 1 {
                        Divider().overlay(Theme.stroke.opacity(0.5)).padding(.leading, 34)
                    }
                }
            }
            .cardStyle()
        }
    }

    private func isCurrent(_ track: Track, _ model: ShowDetailModel) -> Bool {
        engine.currentShow?.identifier == model.show.identifier
            && engine.currentTrack?.id == track.id
    }

    private func sourcesSection(_ model: ShowDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Other Sources").sectionHeaderStyle()
                Spacer()
                Text("\(model.otherRecordings.count)")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text("Same night, different tapes — soundboards, audience mics, and matrix mixes each hear the room differently.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            ForEach(model.otherRecordings.prefix(showingSources ? 30 : 3)) { other in
                Button {
                    Task { await model.switchSource(to: other) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: other.isSoundboard ? "waveform" : "person.wave.2")
                            .foregroundStyle(other.isSoundboard ? Theme.sage : Theme.denim)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(other.identifier)
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            if let rating = other.avgRating, rating > 0 {
                                RatingDots(rating: rating)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(10)
                    .cardStyle()
                }
                .buttonStyle(.plain)
            }
            if model.otherRecordings.count > 3 {
                Button(showingSources ? "Show fewer" : "Show all \(model.otherRecordings.count) sources") {
                    withAnimation(.snappy) { showingSources.toggle() }
                }
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private func notesSection(notes: String?, lineage: String?, fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Taper's Notes").sectionHeaderStyle()
            VStack(alignment: .leading, spacing: 10) {
                if let notes {
                    Text(notes)
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(8)
                }
                if let lineage {
                    Text(lineage)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(4)
                }
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    private func reviewsSection(_ detail: RecordingDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From the Community").sectionHeaderStyle()
            ForEach(Array(detail.reviews.prefix(5).enumerated()), id: \.offset) { _, review in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(review.title ?? "Review")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        if let stars = review.stars, stars > 0 {
                            RatingDots(rating: stars, showValue: false)
                        }
                    }
                    if let body = review.body {
                        Text(body)
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(6)
                    }
                    if let reviewer = review.reviewer {
                        Text("— \(reviewer)")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(Theme.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
        }
    }
}
