import SwiftUI

// The night's memorabilia, kept out of the music's way: the header art is
// a small stacked deck that opens the full-screen viewer, and the scans
// get their own "Memorabilia" section after the setlist. Scans are
// hotlinked from jerrygarcia.com and credited; nothing is drawn over art.

/// Gallery shape for one night, lead (cover) first.
nonisolated struct ScanGallery: Equatable, Sendable {
    var images: [CatalogImage]

    init(images: [CatalogImage] = []) {
        self.images = images
    }

    var lead: CatalogImage? { images.first }
    var hasScans: Bool { !images.isEmpty }
    var count: Int { images.count }

    /// Viewer pages in gallery order, captioned by kind.
    func viewerPages(dateText: String) -> [ImageViewerPage] {
        images.compactMap { scan in
            guard let url = URL(string: scan.url) else { return nil }
            return ImageViewerPage(url: url, caption: scan.kind.label,
                                   accessibilityLabel: "\(scan.kind.label) scan for \(dateText)")
        }
    }

    /// Viewer page index for a scan (URLs that don't parse are skipped).
    func pageIndex(of scan: CatalogImage, dateText: String) -> Int {
        viewerPages(dateText: dateText).firstIndex { $0.url.absoluteString == scan.url } ?? 0
    }

    /// What to present, opening on `scan` (or the lead). Nil when there is
    /// nothing to show.
    func viewerSelection(opening scan: CatalogImage? = nil, dateText: String) -> ScanViewerSelection? {
        let pages = viewerPages(dateText: dateText)
        guard !pages.isEmpty else { return nil }
        let index = scan.map { pageIndex(of: $0, dateText: dateText) } ?? 0
        return ScanViewerSelection(pages: pages, index: index)
    }

    /// "3 scans" / "1 scan", for VoiceOver.
    var countLabel: String {
        count == 1 ? "1 scan" : "\(count) scans"
    }
}

/// What the full-screen viewer opens on. Carrying the pages keeps the
/// cover independent of whichever model produced them.
struct ScanViewerSelection: Identifiable {
    let pages: [ImageViewerPage]
    let index: Int
    var id: Int { index }

    static let credit = "Scan courtesy jerrygarcia.com"
}

extension View {
    /// Presents the scan viewer for a selection, black in both appearances.
    func scanViewer(_ selection: Binding<ScanViewerSelection?>) -> some View {
        fullScreenCover(item: selection) { selected in
            ImageViewer(pages: selected.pages, initialIndex: selected.index,
                        credit: ScanViewerSelection.credit)
        }
    }
}

// MARK: - Deck

/// The header art when the night has scans: the cover in front, with a
/// card peeking out behind it for each further scan (up to two), so the
/// tile itself says "there's more" without a badge over the art.
struct ScanDeck: View {
    let gallery: ScanGallery
    let show: Show
    var size: CGFloat = 92
    let onTap: () -> Void

    /// How far each card behind the cover peeks out.
    static let peek: CGFloat = 4

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topLeading) {
                ForEach(Array((0..<backCards).reversed()), id: \.self) { depth in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.surfaceRaised)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.stroke, lineWidth: 1)
                        )
                        .frame(width: size, height: size)
                        .offset(x: Self.peek * CGFloat(depth + 1), y: Self.peek * CGFloat(depth + 1))
                }
                ShowArtworkView(show: show, coverURL: gallery.lead?.url, size: size)
            }
            .padding([.trailing, .bottom], Self.peek * CGFloat(backCards))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(gallery.lead?.kind.label ?? "Scan"), \(gallery.countLabel)")
        .accessibilityHint("Opens full screen")
    }

    private var backCards: Int {
        Self.backCardCount(for: gallery.count)
    }

    /// Cards behind the cover: none for a lone scan, at most two.
    nonisolated static func backCardCount(for scans: Int) -> Int {
        min(max(scans - 1, 0), 2)
    }
}

// MARK: - Strip

/// Every scan for the night as a horizontal rail of labeled thumbnails,
/// under a "Memorabilia" heading, credited.
struct MemorabiliaSection: View {
    let gallery: ScanGallery
    let onTap: (CatalogImage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Memorabilia").sectionHeaderStyle()
                Spacer()
                Text("\(gallery.count)")
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(gallery.images.enumerated()), id: \.element.id) { offset, scan in
                        ScanThumbnail(scan: scan, position: offset + 1, count: gallery.count) {
                            onTap(scan)
                        }
                    }
                }
            }
            .scrollClipDisabled()
            Text("Scans courtesy jerrygarcia.com")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

struct ScanThumbnail: View {
    let scan: CatalogImage
    /// 1-based position in the gallery, for VoiceOver.
    let position: Int
    let count: Int
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var failed = false

    static let height: CGFloat = 84

    var body: some View {
        if !failed {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Theme.surfaceRaised
                        }
                    }
                    .frame(width: width, height: Self.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
                    Text(scan.kind.shortLabel)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .task(id: scan.url) {
                guard let url = URL(string: scan.url) else {
                    failed = true
                    return
                }
                let loaded = await ArchiveArtwork.shared.image(from: url)
                image = loaded
                failed = loaded == nil
            }
            .accessibilityLabel("\(scan.kind.label) scan, \(position) of \(count)")
            .accessibilityHint("Opens full screen")
        }
    }

    private var width: CGFloat {
        let loaded: Double? = image.map { Double($0.size.width / max($0.size.height, 1)) }
        return Self.height * Self.thumbnailAspect(ratio: scan.aspectRatio ?? loaded)
    }

    /// Thumbnail width:height — square when unknown, up to 2:1 for tickets.
    nonisolated static func thumbnailAspect(ratio: Double?) -> CGFloat {
        guard let ratio, ratio.isFinite, ratio > 0 else { return 1 }
        return CGFloat(min(max(ratio, 1.0), 2.0))
    }
}

// MARK: - Previews

private enum ScanPreviews {
    /// Cornell wearing 3/29/90's scans — a ticket, a poster and a pass.
    static let scans: [CatalogImage] = [
        CatalogImage(date: "1977-05-08", position: 0, kind: .ticket,
                     url: "https://cdn.jerrygarcia.com/wp-content/uploads/1990/03/12151045/t900329.jpeg",
                     width: 319, height: 157),
        CatalogImage(date: "1977-05-08", position: 1, kind: .poster,
                     url: "https://cdn.jerrygarcia.com/wp-content/uploads/1990/03/12152302/19900324.jpeg",
                     width: nil, height: nil),
        CatalogImage(date: "1977-05-08", position: 2, kind: .backstagePass,
                     url: "https://cdn.jerrygarcia.com/wp-content/uploads/1990/03/12151903/b900329.jpeg",
                     width: 324, height: 216),
    ]

    static func environment(scans: [CatalogImage]) -> AppEnvironment {
        let env = AppEnvironment.mock()
        (env.catalog as? MockShowCatalog)?.imagesByDate["1977-05-08"] = scans
        return env
    }
}

#Preview("Deck + memorabilia") {
    NavigationStack {
        ShowDetailScreen(show: MockData.cornell)
    }
    .environment(ScanPreviews.environment(scans: ScanPreviews.scans))
}

#Preview("Single scan") {
    NavigationStack {
        ShowDetailScreen(show: MockData.cornell)
    }
    .environment(ScanPreviews.environment(scans: Array(ScanPreviews.scans.prefix(1))))
}

#Preview("No scans") {
    NavigationStack {
        ShowDetailScreen(show: MockData.cornell)
    }
    .environment(ScanPreviews.environment(scans: []))
}

#Preview("Viewer") {
    ImageViewer(pages: ScanGallery(images: ScanPreviews.scans).viewerPages(dateText: "May 8, 1977"),
                initialIndex: 0, credit: ScanViewerSelection.credit)
}
