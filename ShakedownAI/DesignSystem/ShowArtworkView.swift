import SwiftUI

/// Cover art for a show: the catalog's ticket-stub or poster scan when one
/// exists, the archive's own photo as a second choice (waveform junk filtered
/// out), and a typeset tile otherwise. The generated stub is for the lock
/// screen, not the page.
struct ShowArtworkView: View {
    @Environment(AppEnvironment.self) private var env
    let show: Show
    /// A scan URL the caller already knows (skips the catalog lookup).
    var coverURL: String?
    var size: CGFloat = 96
    var cornerRadius: CGFloat = 12

    @State private var remoteImage: UIImage?

    var body: some View {
        Group {
            if let remoteImage {
                Image(uiImage: remoteImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ArtworkPlaceholder(date: show.displayDate, shortDate: Self.shortDate(show),
                                   venue: show.venue ?? show.title)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .task(id: show.identifier + (show.dateString ?? "") + (coverURL ?? "")) {
            if let coverURL, let url = URL(string: coverURL),
               let scanned = await ArchiveArtwork.shared.image(from: url) {
                remoteImage = scanned
                return
            }
            remoteImage = await ArchiveArtwork.shared.cover(
                date: show.dateString, identifier: show.identifier, catalog: env.catalog)
        }
        .accessibilityHidden(true)
    }

    /// "1972-05-26" → "5/26/72", for tiles too small for the long form.
    static func shortDate(_ show: Show) -> String? {
        guard let ds = show.dateString, ds.count == 10 else { return nil }
        let parts = ds.split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return "\(m)/\(d)/\(parts[0].suffix(2))"
    }
}

/// A square thumbnail for list rows. Kept as a name for the call sites;
/// the lookup chain now lives in `ShowArtworkView`.
struct ShowThumbnail: View {
    let show: Show
    var size: CGFloat = 56

    var body: some View {
        ShowArtworkView(show: show, size: size, cornerRadius: 8)
    }
}

/// What stands in for a scan we don't have: the show's date and venue set
/// on a flat tile, with the reel glyph in the corner like a label on a
/// J-card. Fills whatever frame it's given; below 110pt it shows date only.
struct ArtworkPlaceholder: View {
    var date: String? = nil
    var shortDate: String? = nil
    var venue: String? = nil

    var body: some View {
        GeometryReader { proxy in
            let compact = min(proxy.size.width, proxy.size.height) < 110
            ZStack(alignment: .topLeading) {
                Theme.surfaceRaised
                if compact {
                    VStack(spacing: 4) {
                        Image(systemName: "recordingtape")
                            .font(.footnote)
                            .foregroundStyle(Theme.textTertiary)
                        if let date = shortDate ?? date {
                            Text(date)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(4)
                } else {
                    Image(systemName: "recordingtape")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(10)
                    VStack(alignment: .leading, spacing: 2) {
                        Spacer(minLength: 0)
                        if let date {
                            Text(date)
                                .font(Theme.headline)
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        if let venue, !venue.isEmpty {
                            Text(venue)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
    }
}
