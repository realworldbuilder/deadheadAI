import SwiftUI

/// A show the chat recommended, as a playable card under the reply: art,
/// date, venue, rating, and source on the left (tap to open the show page),
/// a Play button on the right that starts the tape straight from the chat.
struct ChatShowCard: View {
    @Environment(AppEnvironment.self) private var env
    let show: Show
    /// The model's one-line reason for this pick, shown inside the card.
    var note: String?

    @State private var coverURL: String?
    @State private var sourceType: SourceType?
    @State private var isStarting = false
    @State private var playError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // The link and the button are siblings: a NavigationLink
                // wrapping the whole row would swallow the button's taps.
                NavigationLink(value: show) {
                    HStack(spacing: 12) {
                        ShowArtworkView(show: show, coverURL: coverURL, size: 56, cornerRadius: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(show.displayDate)
                                .font(Theme.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(venueLine)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                if let rating = show.avgRating, rating > 0 {
                                    RatingDots(rating: rating)
                                }
                                if let badge {
                                    TagPill(text: badge, tint: Theme.sage)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(show.displayDate), \(show.venue ?? show.title)")
                .accessibilityHint("Opens the show page")

                Button {
                    Task { await play() }
                } label: {
                    ZStack {
                        Circle().fill(Theme.accent)
                        if isStarting {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.onAccent)
                                .offset(x: 1)
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .disabled(isStarting)
                .accessibilityLabel("Play \(show.shortName)")
            }
            if let note {
                Text(ChatLink.render(note, linkColor: Theme.accent))
                    .font(Theme.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let playError {
                Text(playError)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.rose)
            }
        }
        .padding(Theme.cardPadding)
        .cardStyle()
        .task(id: show.identifier) {
            guard env.catalog.isAvailable, let day = show.dateString else { return }
            if coverURL == nil, let night = await env.catalog.show(onDate: day) {
                coverURL = night.coverImageURL
            }
            if sourceType == nil {
                sourceType = await env.catalog.recording(identifier: show.identifier)?.sourceType
            }
        }
    }

    private var venueLine: String {
        [show.venue ?? show.title, show.location].compactMap { $0 }.joined(separator: " · ")
    }

    /// Catalog-detected source when we have it; the identifier sniff otherwise.
    private var badge: String? {
        if let sourceType, sourceType != .unknown { return sourceType.badge }
        return show.isSoundboard ? "SBD" : nil
    }

    /// Same chain the Home hero uses: resolve the tape's tracks, then hand
    /// them to the engine and raise the full player.
    private func play() async {
        guard !isStarting else { return }
        isStarting = true
        playError = nil
        do {
            let detail = try await env.metadataProvider.detail(for: show.identifier)
            if detail.tracks.isEmpty {
                playError = "This tape has no streamable tracks — open the show page to pick another source."
            } else {
                env.playerEngine.play(show: show, tracks: detail.tracks)
                env.playerEngine.isPresentingFullPlayer = true
            }
        } catch HTTPError.serviceUnavailable {
            playError = ArchiveHealth.outageMessage
        } catch {
            playError = "Couldn't reach the archive. Check your connection and try again."
        }
        isStarting = false
    }
}

#Preview {
    ChatShowCard(show: MockData.cornell, note: "The Scarlet > Fire everyone starts with.")
        .padding()
        .environment(AppEnvironment.mock())
}
