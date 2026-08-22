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
    private let downloads: DownloadManager?

    init(show: Show, metadata: any MetadataProvider, recordings: any LiveRecordingProvider,
         ai: any AIProvider, downloads: DownloadManager? = nil) {
        self.show = show
        self.metadata = metadata
        self.recordings = recordings
        self.ai = ai
        self.downloads = downloads
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
            restoreDownloadedSnapshotIfNeeded()
            if detail == nil { errorMessage = ArchiveHealth.outageMessage }
        } catch {
            // A downloaded show should open and play with no network at all.
            restoreDownloadedSnapshotIfNeeded()
            if detail == nil {
                errorMessage = "Couldn't reach the archive. Check your connection and try again."
            }
        }
        isLoading = false
    }

    private func restoreDownloadedSnapshotIfNeeded() {
        guard detail == nil else { return }
        detail = downloads?.store.detailSnapshot(for: show.identifier)
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
    @State private var visibleReviewCount = 5
    @State private var showingJournal = false
    @State private var showingCollectionPicker = false
    @State private var confirmingCancelDownload = false
    @State private var confirmingRemoveDownload = false
    @State private var isSelectingTracks = false
    @State private var selectedTrackIDs: Set<String> = []
    @State private var playlistSheetPayload: PlaylistSheetPayload?

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
                                        ai: env.aiProvider,
                                        downloads: env.downloads)
            }
            await model?.load()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(
                    item: (model?.show ?? show).shareURL,
                    subject: Text((model?.show ?? show).shortName),
                    message: Text((model?.show ?? show).shareText())
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share this show")
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
        .sheet(item: $playlistSheetPayload, onDismiss: {
            withAnimation(.snappy) {
                isSelectingTracks = false
                selectedTrackIDs = []
            }
        }) { payload in
            PlaylistPickerSheet(show: model?.show ?? show, tracks: payload.tracks)
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
                    downloadButton(model, detail: detail)
                    famousRunSection(model, detail: detail)
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
        .safeAreaInset(edge: .bottom) {
            if isSelectingTracks, let detail = model.detail {
                selectionBar(detail)
            }
        }
        .withMiniPlayer()
    }

    /// Floating action bar while track multi-select is active.
    private func selectionBar(_ detail: RecordingDetail) -> some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                withAnimation(.snappy) {
                    isSelectingTracks = false
                    selectedTrackIDs = []
                }
            }
            .font(Theme.mono(13, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                // Setlist order, not tap order.
                let tracks = detail.tracks.filter { selectedTrackIDs.contains($0.id) }
                playlistSheetPayload = PlaylistSheetPayload(tracks: tracks)
            } label: {
                Text(selectedTrackIDs.isEmpty
                     ? "Select tracks"
                     : "Add \(selectedTrackIDs.count) to Playlist")
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.accentGradient))
            }
            .disabled(selectedTrackIDs.isEmpty)
            .opacity(selectedTrackIDs.isEmpty ? 0.6 : 1)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
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
    private func downloadButton(_ model: ShowDetailModel, detail: RecordingDetail) -> some View {
        let identifier = model.show.identifier
        let state = env.downloads.displayState(for: identifier)
        Button {
            switch state {
            case .notDownloaded:
                env.downloads.download(show: model.show, detail: detail)
            case .inProgress:
                confirmingCancelDownload = true
            case .downloaded:
                confirmingRemoveDownload = true
            case .failed:
                env.downloads.retry(identifier: identifier)
            }
        } label: {
            VStack(spacing: 8) {
                HStack {
                    downloadLabel(for: state)
                    Spacer()
                }
                if case .inProgress(let progress) = state {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.stroke.opacity(0.6))
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: max(4, geo.size.width * progress.fraction))
                        }
                    }
                    .frame(height: 3)
                    .animation(.snappy, value: progress.fraction)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(detail.tracks.isEmpty)
        .confirmationDialog("Stop this download?", isPresented: $confirmingCancelDownload, titleVisibility: .visible) {
            Button("Stop & Remove", role: .destructive) {
                env.downloads.cancelAndDelete(identifier: identifier)
            }
        }
        .confirmationDialog("Remove this download?", isPresented: $confirmingRemoveDownload, titleVisibility: .visible) {
            Button("Remove Download", role: .destructive) {
                env.downloads.cancelAndDelete(identifier: identifier)
            }
        } message: {
            Text("You can stream it any time, or download it again.")
        }
    }

    @ViewBuilder
    private func downloadLabel(for state: DownloadManager.DisplayState) -> some View {
        switch state {
        case .notDownloaded:
            Label("Download Show", systemImage: "arrow.down.circle")
                .font(Theme.mono(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        case .inProgress(let progress):
            Label("Downloading… \(min(progress.completedTracks + 1, progress.totalTracks)) of \(progress.totalTracks)",
                  systemImage: "arrow.down.circle.dotted")
                .font(Theme.mono(13, weight: .semibold))
                .foregroundStyle(Theme.accent)
        case .downloaded(let bytes):
            Label(bytes > 0
                    ? "Downloaded · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
                    : "Downloaded",
                  systemImage: "checkmark.circle.fill")
                .font(Theme.mono(13, weight: .semibold))
                .foregroundStyle(Theme.sage)
        case .failed(let done, let total):
            Label("Download incomplete (\(done) of \(total)) — Retry", systemImage: "exclamationmark.arrow.circlepath")
                .font(Theme.mono(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    /// Curated famous runs anchored to this exact transfer — only rendered
    /// when the song sequence actually resolves against the tape's tracks.
    @ViewBuilder
    private func famousRunSection(_ model: ShowDetailModel, detail: RecordingDetail) -> some View {
        let day = detail.dateString ?? model.show.dateString ?? ""
        let resolved = env.knowledgeBase.runs(on: day).compactMap { run in
            RunResolver.resolve(run, in: detail.tracks).map { (run: run, range: $0) }
        }
        ForEach(resolved, id: \.run.id) { entry in
            FamousRunCard(run: entry.run, range: entry.range, tracks: detail.tracks) {
                engine.play(show: model.show, tracks: detail.tracks, startAt: entry.range.lowerBound)
                engine.isPresentingFullPlayer = true
            }
        }
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
                        if isSelectingTracks {
                            toggleSelection(track)
                        } else {
                            engine.play(show: model.show, tracks: detail.tracks, startAt: index)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isSelectingTracks {
                                Image(systemName: selectedTrackIDs.contains(track.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(selectedTrackIDs.contains(track.id)
                                                     ? Theme.accent : Theme.textTertiary)
                                    .contentTransition(.symbolEffect(.replace))
                            } else {
                                Text(String(format: "%02d", index + 1))
                                    .font(Theme.mono(12))
                                    .foregroundStyle(isCurrent(track, model) ? Theme.accent : Theme.textTertiary)
                            }
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
                    .contextMenu {
                        Button {
                            playlistSheetPayload = PlaylistSheetPayload(tracks: [track])
                        } label: {
                            Label("Add to Playlist…", systemImage: "music.note.list")
                        }
                        Button {
                            withAnimation(.snappy) {
                                isSelectingTracks = true
                                selectedTrackIDs = [track.id]
                            }
                        } label: {
                            Label("Select Tracks…", systemImage: "checklist")
                        }
                    }
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

    private func toggleSelection(_ track: Track) {
        if selectedTrackIDs.contains(track.id) {
            selectedTrackIDs.remove(track.id)
        } else {
            selectedTrackIDs.insert(track.id)
        }
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
            ForEach(Array(detail.reviews.prefix(visibleReviewCount).enumerated()), id: \.offset) { _, review in
                ReviewCard(review: review)
            }
            if detail.reviews.count > 5 {
                HStack(spacing: 16) {
                    if visibleReviewCount < detail.reviews.count {
                        Button("Show more (\(detail.reviews.count - visibleReviewCount) left)") {
                            withAnimation(.snappy) { visibleReviewCount += 5 }
                        }
                    }
                    if visibleReviewCount > 5 {
                        Button("Show fewer") {
                            withAnimation(.snappy) { visibleReviewCount = 5 }
                        }
                    }
                }
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }
        }
    }
}

/// Wraps the tracks headed to the playlist picker so sheet(item:) has identity.
private struct PlaylistSheetPayload: Identifiable {
    let id = UUID()
    let tracks: [Track]
}

/// "The run people talk about" card: curated canon, playable in one tap.
struct FamousRunCard: View {
    let run: FamousRun
    let range: ClosedRange<Int>
    let tracks: [Track]
    let onPlay: () -> Void

    private var runLength: String {
        let count = "\(range.count) track\(range.count == 1 ? "" : "s")"
        let seconds = tracks[range].compactMap(\.durationSeconds).reduce(0, +)
        guard seconds > 0 else { return count }
        let minutes = Int((seconds / 60).rounded())
        return "\(count) · \(minutes) min"
    }

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                    Text("FAMOUS RUN")
                        .font(Theme.mono(11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Text(runLength)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(run.title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(run.blurb)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                    Text("Play the run")
                        .font(Theme.mono(12, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(raised: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ReviewCard: View {
    let review: Review
    @State private var isExpanded = false

    private var isLongBody: Bool {
        guard let body = review.body else { return false }
        return body.count > 280 || body.filter(\.isNewline).count >= 6
    }

    var body: some View {
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
                    .lineLimit(isExpanded ? nil : 6)
            }
            if isLongBody {
                Button(isExpanded ? "Show less" : "Read more") {
                    withAnimation(.snappy) { isExpanded.toggle() }
                }
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(Theme.accent)
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
