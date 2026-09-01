import SwiftUI

/// Square-art show card for horizontal rails: the ticket stub, poster, or
/// archive photo is the face of the show, with a source badge burned into
/// the corner — date and venue beneath.
struct ShowCard: View {
    @Environment(AppEnvironment.self) private var env
    let show: Show
    var width: CGFloat = 148

    @State private var coverURL: String?
    @State private var sourceType: SourceType?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                ShowArtworkView(show: show, coverURL: coverURL, size: width, cornerRadius: 10)
                sourceBadge
                    .padding(6)
            }
            Text(show.displayDate)
                .font(Theme.mono(13, weight: .bold))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
            Text(show.venue ?? show.title)
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(show.location ?? " ")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .task(id: show.identifier) {
            guard env.catalog.isAvailable, let day = show.dateString else { return }
            if coverURL == nil, let night = await env.catalog.show(onDate: day) {
                coverURL = night.coverImageURL
            }
            if sourceType == nil {
                sourceType = await env.catalog.recording(identifier: show.identifier)?.sourceType
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(show.displayDate), \(show.venue ?? "")")
    }

    @ViewBuilder
    private var sourceBadge: some View {
        let badge: String? = {
            if let sourceType, sourceType != .unknown { return sourceType.badge }
            return show.isSoundboard ? "SBD" : nil
        }()
        if let badge {
            Text(badge)
                .font(Theme.mono(10, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.65)))
        }
    }
}

/// A titled horizontal rail of show cards.
struct ShowRail: View {
    let title: String
    var subtitle: String?
    let shows: [Show]
    var icon: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(Theme.accent)
                }
                Text(title).sectionHeaderStyle()
            }
            if let subtitle {
                Text(subtitle)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(shows) { show in
                        NavigationLink(value: show) {
                            ShowCard(show: show)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}
