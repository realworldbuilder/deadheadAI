import SwiftUI

/// Every show saved for offline listening, with live progress for in-flight
/// downloads and per-show removal.
struct DownloadsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmingDelete: String?

    var body: some View {
        ZStack {
            SpaceBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // changeToken re-runs the fetch after store mutations.
                    let _ = env.downloads.store.changeToken
                    let records = env.downloads.store.allRecords()
                    if records.isEmpty {
                        emptyState
                    } else {
                        summaryLine(records: records)
                        ForEach(records, id: \.identifier) { record in
                            row(record)
                        }
                    }
                }
                .padding(Theme.screenPadding)
            }
            .withMiniPlayer()
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .confirmationDialog("Remove this download?",
                            isPresented: Binding(get: { confirmingDelete != nil },
                                                 set: { if !$0 { confirmingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Remove Download", role: .destructive) {
                if let identifier = confirmingDelete {
                    env.downloads.cancelAndDelete(identifier: identifier)
                }
                confirmingDelete = nil
            }
        } message: {
            Text("You can stream it any time, or download it again.")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing saved yet")
                .font(Theme.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Open any show and tap Download to keep it on this device — perfect for flights, road trips, and basements with no bars.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func summaryLine(records: [DownloadedShowRecord]) -> some View {
        let total = records.reduce(Int64(0)) { $0 + $1.totalBytes }
        return Text("\(records.count) \(records.count == 1 ? "show" : "shows") · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
            .font(Theme.mono(12))
            .foregroundStyle(Theme.textTertiary)
    }

    @ViewBuilder
    private func row(_ record: DownloadedShowRecord) -> some View {
        let show = try? JSONDecoder().decode(Show.self, from: record.showPayload)
        let state = env.downloads.displayState(for: record.identifier)
        NavigationLink(value: show ?? Show(identifier: record.identifier, title: record.identifier,
                                           date: nil, dateString: nil, venue: nil, location: nil,
                                           year: nil, avgRating: nil, numReviews: nil,
                                           downloads: nil, source: nil)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    statusIcon(state)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(show?.shortName ?? record.identifier)
                            .font(Theme.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(subtitle(record: record, state: state))
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        confirmingDelete = record.identifier
                    } label: {
                        Image(systemName: "trash")
                            .font(.footnote)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove download")
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
            .padding(14)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusIcon(_ state: DownloadManager.DisplayState) -> some View {
        switch state {
        case .downloaded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sage)
        case .inProgress:
            ProgressView().tint(Theme.accent)
        case .failed:
            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.accent)
        case .notDownloaded:
            Image(systemName: "arrow.down.circle").foregroundStyle(Theme.textTertiary)
        }
    }

    private func subtitle(record: DownloadedShowRecord, state: DownloadManager.DisplayState) -> String {
        switch state {
        case .downloaded(let bytes):
            let size = bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : "on device"
            return "\(record.trackRecords.count) tracks · \(size)"
        case .inProgress(let progress):
            return "Downloading… \(min(progress.completedTracks + 1, progress.totalTracks)) of \(progress.totalTracks)"
        case .failed(let done, let total):
            return "Incomplete — \(done) of \(total) tracks. Open the show to retry."
        case .notDownloaded:
            return "\(record.trackRecords.count) tracks"
        }
    }
}
