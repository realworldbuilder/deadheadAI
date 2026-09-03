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
    /// The real setlist from the bundled catalog (nil when unknown).
    var setlist: Setlist?
    /// Build-time consensus of this night's archive reviews.
    var digest: ShowDigest?
    /// Catalog facts about tapes of this night, keyed by identifier —
    /// source type, taper, review counts for the source picker rows.
    var catalogRecordings: [String: CatalogRecording] = [:]
    /// Taper-spelling → canonical song key, for setlist↔track alignment.
    var songAliases: [String: String] = [:]
    /// Ticket stub / poster scan URL for this night, from the catalog.
    var coverImageURL: String?
    /// Every memorabilia scan for this night, cover first (see `ScanGallery`).
    var images: [CatalogImage] = []
    var gallery: ScanGallery { ScanGallery(images: images) }

    private let metadata: any MetadataProvider
    private let recordings: any LiveRecordingProvider
    private let ai: any AIProvider
    private let downloads: DownloadManager?
    private let catalog: (any ShowCatalog)?

    init(show: Show, metadata: any MetadataProvider, recordings: any LiveRecordingProvider,
         ai: any AIProvider, downloads: DownloadManager? = nil, catalog: (any ShowCatalog)? = nil) {
        self.show = show
        self.metadata = metadata
        self.recordings = recordings
        self.ai = ai
        self.downloads = downloads
        self.catalog = catalog
    }

    /// Catalog source type for the tape currently in front of the user.
    var sourceType: SourceType? {
        catalogRecordings[show.identifier]?.sourceType
    }

    func loadCatalogContext() async {
        guard let catalog, catalog.isAvailable, let day = show.dateString else { return }
        if setlist == nil {
            setlist = await catalog.setlist(forDate: day)
        }
        if songAliases.isEmpty {
            songAliases = await catalog.songAliases()
        }
        if images.isEmpty {
            images = await catalog.images(onDate: day)
        }
        if catalogRecordings.isEmpty {
            for night in await catalog.shows(onDate: day) {
                if digest == nil {
                    digest = await catalog.digest(forShow: night.showID)
                }
                if coverImageURL == nil {
                    coverImageURL = night.coverImageURL
                }
                for recording in await catalog.recordings(forShow: night.showID) {
                    catalogRecordings[recording.identifier] = recording
                }
            }
        }
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
        await loadCatalogContext()
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
    @State private var viewerSelection: ScanViewerSelection?

    let show: Show

    var body: some View {
        // A ZStack, not a Group: with `model` nil a Group has no children,
        // so the `.task` below would never run to create it.
        ZStack {
            if let model {
                content(model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .task {
            if model == nil {
                let fresh = ShowDetailModel(show: show,
                                            metadata: env.metadataProvider,
                                            recordings: env.recordingProvider,
                                            ai: env.aiProvider,
                                            downloads: env.downloads,
                                            catalog: env.catalog)
                // The catalog is local SQLite: resolve it before the first
                // paint so the hero doesn't pop in above the header.
                await fresh.loadCatalogContext()
                model = fresh
                stageScansIfRequested(fresh)
            }
            await model?.load()
        }
        .navigationBarTitleDisplayMode(.inline)
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
        .scanViewer($viewerSelection)
    }

    private func openViewer(_ model: ShowDetailModel, scan: CatalogImage? = nil) {
        viewerSelection = model.gallery.viewerSelection(opening: scan, dateText: model.show.displayDate)
    }

    /// Debug hook: `--stage-scans` opens the viewer on the first scan for
    /// CLI screenshot capture (simctl can't tap).
    private func stageScansIfRequested(_ model: ShowDetailModel) {
        guard ProcessInfo.processInfo.arguments.contains("--stage-scans") else { return }
        openViewer(model)
    }

    @ViewBuilder
    private func content(_ model: ShowDetailModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                header(model)

                if model.isLoading && model.detail == nil {
                    LoadingLampView(text: "Tuning in from the archive…")
                } else if let error = model.errorMessage {
                    ErrorCard(message: error) {
                        Task { await model.load() }
                    }
                } else if let detail = model.detail {
                    VStack(spacing: 10) {
                        playButton(model, detail: detail)
                        downloadButton(model, detail: detail)
                    }
                    famousRunSection(model, detail: detail)
                    guideSection(model)
                    let marks = model.guide.map {
                        GuideTrackMarks.marks(for: $0, tracks: detail.tracks, aliases: model.songAliases)
                    } ?? [:]
                    trackList(detail, model: model, marks: marks)
                    if model.gallery.hasScans {
                        MemorabiliaSection(gallery: model.gallery) { scan in
                            openViewer(model, scan: scan)
                        }
                    }
                    if !model.otherRecordings.isEmpty {
                        sourcesSection(model)
                    }
                    if let notes = detail.notes ?? detail.lineage {
                        notesSection(notes: detail.notes, lineage: detail.lineage, fallback: notes)
                    }
                    if let digest = model.digest {
                        digestCard(digest)
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
            .buttonStyle(.secondary)
            Spacer()
            Button {
                // Setlist order, not tap order.
                let tracks = detail.tracks.filter { selectedTrackIDs.contains($0.id) }
                playlistSheetPayload = PlaylistSheetPayload(tracks: tracks)
            } label: {
                Text(selectedTrackIDs.isEmpty
                     ? "Select tracks"
                     : "Add \(selectedTrackIDs.count) to Playlist")
            }
            .buttonStyle(.primary)
            .disabled(selectedTrackIDs.isEmpty)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { HairlineDivider() }
    }

    /// With scans, the art is a tappable deck into the viewer; without,
    /// the plain tile and its borrowed-scan fallbacks, as before.
    private func header(_ model: ShowDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                if model.gallery.hasScans {
                    ScanDeck(gallery: model.gallery, show: model.show) { openViewer(model) }
                } else {
                    ShowArtworkView(show: model.show, coverURL: model.coverImageURL, size: 92)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.show.displayDate)
                        .font(Theme.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text(model.show.venue ?? model.show.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let location = model.show.location {
                        Text(location)
                            .font(Theme.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            HStack(spacing: 8) {
                // Prefer the pipeline's source detection over the old
                // identifier substring sniff, which stays as the fallback.
                if let sourceType = model.sourceType, sourceType != .unknown {
                    TagPill(text: sourceType.displayName,
                            tint: sourceType == .audience ? Theme.denim : Theme.sage)
                } else if model.show.isSoundboard {
                    TagPill(text: "Soundboard", tint: Theme.sage)
                }
                if model.show.isMillerTransfer { TagPill(text: "Miller", tint: Theme.denim) }
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
                Spacer()
                Text("\(detail.tracks.count) tracks")
                    .font(Theme.footnote)
                    .opacity(0.8)
            }
        }
        .buttonStyle(.primary(fullWidth: true))
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
                    ProgressView(value: progress.fraction)
                        .tint(Theme.accent)
                        .animation(.snappy, value: progress.fraction)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
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
                .font(Theme.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        case .inProgress(let progress):
            Label("Downloading… \(min(progress.completedTracks + 1, progress.totalTracks)) of \(progress.totalTracks)",
                  systemImage: "arrow.down.circle.dotted")
                .font(Theme.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        case .downloaded(let bytes):
            Label(bytes > 0
                    ? "Downloaded · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
                    : "Downloaded",
                  systemImage: "checkmark.circle.fill")
                .font(Theme.subheadline.weight(.semibold))
                .foregroundStyle(Theme.sage)
        case .failed(let done, let total):
            Label("Download incomplete (\(done) of \(total)) — Retry", systemImage: "exclamationmark.arrow.circlepath")
                .font(Theme.subheadline.weight(.semibold))
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
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Listening Guide")
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Mood, history, transitions, and what to listen for.")
                            .font(Theme.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if model.isLoadingGuide {
                        ProgressView().tint(Theme.textSecondary)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(Theme.cardPadding)
                .cardStyle()
            }
            .buttonStyle(.plain)
            .disabled(model.isLoadingGuide)
        }
    }

    /// What the community agrees on — computed at build time from every
    /// archive.org review of this night, readable with zero network.
    private func digestCard(_ digest: ShowDigest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fan Consensus").sectionHeaderStyle()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    RatingDots(rating: digest.derivedRating)
                    Text(digest.sentiment)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(digest.consensusSummary)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !digest.standoutSongs.isEmpty {
                    Text("Standouts: " + digest.standoutSongs.joined(separator: " · "))
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(digest.ratingRationale)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One list for the whole night: the tape's tracks in order, shaped by
    /// the catalog setlist — set headings where the sets break, segue marks
    /// on the matched tracks, and songs the tape is missing dimmed in place.
    private func trackList(_ detail: RecordingDetail, model: ShowDetailModel,
                           marks: [Int: GuideMarks]) -> some View {
        let rows = TapeSetlist.rows(setlist: model.setlist, tracks: detail.tracks,
                                    aliases: model.songAliases)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Setlist").sectionHeaderStyle()
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                    let isLast = position == rows.count - 1
                    let divider = !isLast && !rows[position + 1].isHeading
                    switch row {
                    case .heading(let label):
                        Text(label)
                            .eyebrowStyle()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, position == 0 ? 0 : 16)
                            .padding(.bottom, 4)
                    case .track(let index, let segues):
                        trackRow(detail.tracks[index], index: index, segues: segues,
                                 divider: divider, detail: detail, model: model, marks: marks)
                    case .missing(let entry):
                        missingRow(entry, divider: divider)
                    }
                }
            }
            if model.setlist?.status == .partial {
                Text("Partial setlist — reconstructed from taper notes.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 8)
            }
            if rows.contains(where: \.isMissing) {
                Text("Dimmed songs aren't on this tape.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 8)
            }
            let used = marks.values.reduce(GuideMarks()) { $0.union($1) }
            if !used.isEmpty {
                GuideMarkLegend(marks: used)
            }
        }
    }

    private func trackRow(_ track: Track, index: Int, segues: Bool, divider: Bool,
                          detail: RecordingDetail, model: ShowDetailModel,
                          marks: [Int: GuideMarks]) -> some View {
        Button {
            if isSelectingTracks {
                toggleSelection(track)
            } else {
                engine.play(show: model.show, tracks: detail.tracks, startAt: index)
            }
        } label: {
            HStack(spacing: 12) {
                if isSelectingTracks {
                    Image(systemName: selectedTrackIDs.contains(track.id)
                          ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selectedTrackIDs.contains(track.id)
                                         ? Theme.accent : Theme.textTertiary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 24)
                } else {
                    Text(String(format: "%02d", index + 1))
                        .font(Theme.timecode)
                        .foregroundStyle(isCurrent(track, model) ? Theme.accent : Theme.textTertiary)
                        .frame(width: 24, alignment: .leading)
                }
                Text(track.displayTitle)
                    .font(isCurrent(track, model) ? Theme.body.weight(.semibold) : Theme.body)
                    .foregroundStyle(isCurrent(track, model) ? Theme.accent : Theme.textPrimary)
                    .lineLimit(1)
                GuideMarkGlyphs(marks: marks[index] ?? [])
                if segues {
                    SegueMark()
                }
                Spacer()
                Text(track.displayDuration)
                    .font(Theme.timecode)
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowStyle(divider: divider)
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
    }

    /// A setlist song this tape doesn't carry: dimmed, unnumbered, inert.
    private func missingRow(_ entry: SetlistEntry, divider: Bool) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 24, height: 1)
            Text(entry.songTitle)
                .font(Theme.body)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            if entry.seguesIntoNext {
                SegueMark()
            }
            Spacer()
        }
        .listRowStyle(divider: divider)
        .accessibilityLabel("\(entry.songTitle), not on this tape")
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
        let visible = Array(model.otherRecordings.prefix(showingSources ? 30 : 3))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Other Sources").sectionHeaderStyle()
                Spacer()
                Text("\(model.otherRecordings.count)")
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            Text("Same night, different tapes — soundboards, audience mics, and matrix mixes each hear the room differently.")
                .font(Theme.footnote)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, other in
                    Button {
                        Task { await model.switchSource(to: other) }
                    } label: {
                        sourceRow(other, model: model, divider: index < visible.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.otherRecordings.count > 3 {
                Button(showingSources ? "Show fewer" : "Show all \(model.otherRecordings.count) sources") {
                    withAnimation(.snappy) { showingSources.toggle() }
                }
                .font(Theme.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)
            }
        }
    }

    /// "SBD · ★4.8 (156 reviews) · Betty Cantor" when the catalog knows this
    /// tape; identifier + rating dots otherwise.
    private func sourceRow(_ other: Show, model: ShowDetailModel, divider: Bool) -> some View {
        let info = model.catalogRecordings[other.identifier]
        let sourceType = info?.sourceType ?? (other.isSoundboard ? .soundboard : .unknown)
        let tint = sourceType == .audience || sourceType == .unknown ? Theme.denim : Theme.sage
        let isDownloaded: Bool = {
            if case .downloaded = env.downloads.displayState(for: other.identifier) { return true }
            return false
        }()
        return HStack(spacing: 12) {
            Image(systemName: sourceType.systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(sourceType.badge)
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    if let rating = other.avgRating, rating > 0 {
                        RatingDots(rating: rating, showValue: true)
                    }
                    if let reviews = other.numReviews, reviews > 0 {
                        Text("(\(reviews))")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.sage)
                    }
                }
                Text(info?.taper.map { "Taper: \($0)" } ?? other.identifier)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .listRowStyle(divider: divider)
        .contentShape(Rectangle())
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
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(4)
                }
            }
        }
    }

    private func reviewsSection(_ detail: RecordingDetail) -> some View {
        let reviews = Array(detail.reviews.prefix(visibleReviewCount))
        return VStack(alignment: .leading, spacing: 4) {
            Text("From the Community").sectionHeaderStyle()
            VStack(spacing: 0) {
                ForEach(Array(reviews.enumerated()), id: \.offset) { index, review in
                    ReviewCard(review: review, divider: index < reviews.count - 1)
                }
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
                .font(Theme.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)
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
                    Text("Famous run")
                        .font(Theme.footnote.weight(.semibold))
                    Spacer()
                    Text(runLength)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .foregroundStyle(Theme.textSecondary)
                Text(run.title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(run.blurb)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                    Text("Play the run")
                        .font(Theme.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ReviewCard: View {
    let review: Review
    var divider = true
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
                .font(Theme.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            }
            if let reviewer = review.reviewer {
                Text("— \(reviewer)")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .listRowStyle(divider: divider)
    }
}

/// The setlist's segue marker, shown after a song that runs into the next.
private struct SegueMark: View {
    var body: some View {
        Text(">")
            .font(Theme.subheadline.weight(.semibold))
            .foregroundStyle(Theme.denim)
    }
}
