import SwiftUI

/// Square-art show card for horizontal rails: the ticket stub, poster, or
/// archive photo is the face of the show, with date, venue, and source
/// beneath. Nothing is drawn over the art.
struct ShowCard: View {
    @Environment(AppEnvironment.self) private var env
    let show: Show
    var width: CGFloat = 148

    @State private var coverURL: String?
    @State private var sourceType: SourceType?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ShowArtworkView(show: show, coverURL: coverURL, size: width, cornerRadius: 10)
            Text(show.displayDate)
                .font(Theme.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(show.venue ?? show.title)
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Text(detailLine)
                .font(.caption2)
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

    /// "SBD · Ithaca, NY" — the source leads when we know it.
    private var detailLine: String {
        let badge: String? = {
            if let sourceType, sourceType != .unknown { return sourceType.badge }
            return show.isSoundboard ? "SBD" : nil
        }()
        let parts = [badge, show.location].compactMap { $0 }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
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
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(title).sectionHeaderStyle()
            }
            if let subtitle {
                Text(subtitle)
                    .font(Theme.footnote)
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
