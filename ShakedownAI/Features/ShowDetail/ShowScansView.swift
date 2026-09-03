import SwiftUI

// The night's memorabilia on the show page: the lead scan (the cover)
// fills a full-bleed hero, the rest ride a thumbnail strip, and any of
// them opens the full-screen viewer. Scans are hotlinked from
// jerrygarcia.com and credited; nothing is drawn over the art.

/// Gallery shape for one night, lead (cover) first.
nonisolated struct ScanGallery: Equatable, Sendable {
    var images: [CatalogImage]

    init(images: [CatalogImage] = []) {
        self.images = images
    }

    var lead: CatalogImage? { images.first }
    var others: [CatalogImage] { Array(images.dropFirst()) }
    var hasScans: Bool { !images.isEmpty }
    /// One scan is the hero; a strip only earns its space with a second.
    var showsStrip: Bool { images.count >= 2 }

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
}

enum RemoteScanPhase: Equatable {
    case loading, failed
}

/// One remote scan through `ArchiveArtwork`'s cache, so the hero, its
/// thumbnail and the viewer page all share a single download.
struct RemoteScanImage<Content: View, Placeholder: View>: View {
    let url: URL
    @ViewBuilder let content: (UIImage) -> Content
    @ViewBuilder let placeholder: (RemoteScanPhase) -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                placeholder(failed ? .failed : .loading)
            }
        }
        .task(id: url) {
            let loaded = await ArchiveArtwork.shared.image(from: url)
            image = loaded
            failed = loaded == nil
        }
    }
}

// MARK: - Hero

/// The lead scan, edge to edge above the show header. Sized by the scan's
/// own aspect (tickets sit short and wide, posters tall) within limits, so
/// the page never opens on a wall of poster or a sliver of stub.
struct ScanHero: View {
    let image: CatalogImage
    let show: Show
    let onTap: () -> Void

    @State private var loadedSize: CGSize?

    var body: some View {
        Button(action: onTap) {
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .overlay(alignment: alignment) {
                    if let url = URL(string: image.url) {
                        RemoteScanImage(url: url) { loaded in
                            Image(uiImage: loaded)
                                .resizable()
                                .scaledToFill()
                                .onAppear { loadedSize = loaded.size }
                        } placeholder: { phase in
                            if phase == .failed {
                                placeholderTile
                            } else {
                                Theme.surface
                            }
                        }
                    } else {
                        placeholderTile
                    }
                }
                .clipped()
                .animation(.snappy, value: loadedSize)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(image.kind.label) scan for \(show.displayDate)")
        .accessibilityHint("Opens full screen")
    }

    private var placeholderTile: some View {
        ArtworkPlaceholder(date: show.displayDate, shortDate: ShowArtworkView.shortDate(show),
                           venue: show.venue ?? show.title)
    }

    private var aspect: CGFloat {
        Self.bannerAspect(ratio: image.aspectRatio ?? loadedRatio)
    }

    private var alignment: Alignment {
        Self.cropAlignment(kind: image.kind,
                           width: image.width ?? loadedSize.map { Int($0.width) },
                           height: image.height ?? loadedSize.map { Int($0.height) })
    }

    private var loadedRatio: Double? {
        guard let loadedSize, loadedSize.height > 0 else { return nil }
        return loadedSize.width / loadedSize.height
    }

    /// Banner width:height. Unknown → 16:9 (Home's hero height on a phone);
    /// known → the scan's own ratio, clamped so a ticket isn't a sliver
    /// and a poster isn't a wall.
    nonisolated static func bannerAspect(width: Int?, height: Int?) -> CGFloat {
        guard let width, let height, width > 0, height > 0 else { return bannerAspect(ratio: nil) }
        return bannerAspect(ratio: Double(width) / Double(height))
    }

    nonisolated static func bannerAspect(ratio: Double?) -> CGFloat {
        guard let ratio, ratio.isFinite, ratio > 0 else { return 16.0 / 9.0 }
        return CGFloat(min(max(ratio, 1.25), 2.4))
    }

    /// Where the crop keeps its detail: posters and portrait scans carry
    /// their title at the top; everything else centers.
    nonisolated static func cropAlignment(kind: CatalogImage.Kind, width: Int?, height: Int?) -> Alignment {
        if kind == .poster { return .top }
        if let width, let height, height > width { return .top }
        return .center
    }
}

// MARK: - Strip

/// The scans after the lead, as a horizontal rail of labeled thumbnails.
struct ScanStrip: View {
    let gallery: ScanGallery
    let dateText: String
    let onTap: (CatalogImage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(gallery.others.enumerated()), id: \.element.id) { offset, scan in
                        ScanThumbnail(scan: scan, position: offset + 2, count: gallery.images.count) {
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

    static let height: CGFloat = 72

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
        CatalogImage(date: "1977-05-08", position: 0, kind: .ticket, url: "https://cdn.jerrygarcia.com/wp-content/uploads/1990/03/12151045/t900329.jpeg", width: 319, height: 157),
        CatalogImage(date: "1977-05-08", position: 0, kind: .poster, url: "https://cdn.jerrygarcia.com/wp-content/uploads/1990/03/12152302/19900324.jpeg", width: nil, height: nil),
        CatalogImage(date: "1977-05-08", position: 0, kind: .backstagePass, url: "https://cdn.jerrygarcia.com/wp-content/uploads/1990/03/12151903/b900329.jpeg", width: 324, height: 216)
    ]

    static func environment(scans: [CatalogImage]) -> AppEnvironment {
        let env = AppEnvironment.mock()
        (env.catalog as? MockShowCatalog)?.imagesByDate["1977-05-08"] = scans
        return env
    }
}

#Preview("Hero + strip") {
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
                initialIndex: 0, credit: "Scan courtesy jerrygarcia.com")
}
