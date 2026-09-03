import UIKit

/// Fetches archive.org's per-item tile image
/// (`archive.org/services/img/{identifier}`) — often a real photo or a
/// scanned ticket stub — and rejects the waveform screenshots many
/// transfers use as their thumbnail, so junk never becomes cover art.
/// Callers fall back to the generated ticket-stub artwork.
final class ArchiveArtwork {
    static let shared = ArchiveArtwork()

    private let cache = NSCache<NSString, UIImage>()
    /// Keys whose image definitely doesn't exist (404, junk, waveform) —
    /// don't re-fetch this run. Network hiccups and cancelled callers are
    /// never recorded here, so the next appearance tries again.
    private var misses = Set<String>()
    /// One download per key, shared by everyone waiting on it. The task is
    /// unstructured on purpose: when SwiftUI cancels a row's `.task` mid-
    /// scroll, the download finishes anyway and lands in the cache.
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    /// Fetch any remote cover (e.g. a jerrygarcia.com ticket-stub scan
    /// from the catalog). No waveform filter — these are curated scans.
    func image(from url: URL) async -> UIImage? {
        await load(key: url.absoluteString, url: url, filterWaveforms: false)
    }

    /// archive.org's per-item tile, with waveform screenshots rejected.
    func thumbnail(for identifier: String) async -> UIImage? {
        guard let url = URL(string: "https://archive.org/services/img/\(identifier)") else { return nil }
        return await load(key: identifier, url: url, filterWaveforms: true)
    }

    private func load(key: String, url: URL, filterWaveforms: Bool) async -> UIImage? {
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if misses.contains(key) { return nil }
        if let running = inflight[key] { return await running.value }
        let task = Task<UIImage?, Never> {
            let outcome = await Self.download(url, filterWaveforms: filterWaveforms)
            inflight[key] = nil
            switch outcome {
            case .image(let image):
                cache.setObject(image, forKey: key as NSString)
                return image
            case .missing:
                misses.insert(key)
                return nil
            case .transient:
                return nil
            }
        }
        inflight[key] = task
        return await task.value
    }

    private enum Outcome {
        case image(UIImage)
        /// The server answered and there is no usable image.
        case missing
        /// No answer (offline, timeout, throttled): try again later.
        case transient
    }

    nonisolated private static func download(_ url: URL, filterWaveforms: Bool) async -> Outcome {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else {
            return .transient
        }
        guard let http = response as? HTTPURLResponse else { return .transient }
        if http.statusCode == 429 || http.statusCode >= 500 { return .transient }
        guard http.statusCode == 200, let image = UIImage(data: data), image.size.width >= 50 else {
            return .missing
        }
        if filterWaveforms, !looksLikeRealArt(image) { return .missing }
        return .image(image)
    }

    /// Waveform thumbnails are mostly near-white background with a thin
    /// dark trace; real photos and stub scans aren't. Downsample and count.
    nonisolated static func looksLikeRealArt(_ image: UIImage) -> Bool {
        guard image.size.width >= 50, image.size.height >= 50,
              let cgImage = image.cgImage else { return false }
        let side = 16
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let pixels = context.data else { return true }
        let buffer = pixels.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var bright = 0
        for i in 0..<(side * side) {
            let r = Int(buffer[i * 4]), g = Int(buffer[i * 4 + 1]), b = Int(buffer[i * 4 + 2])
            if r > 215 && g > 215 && b > 215 { bright += 1 }
        }
        return Double(bright) / Double(side * side) < 0.5
    }
}

extension ArchiveArtwork {
    /// One resolver for every card: the jerrygarcia.com scan for the date
    /// if the catalog has one, else the archive item tile (filtered),
    /// else nil — caller falls back to the generated stub.
    @MainActor
    /// The best picture we can put on a show: its own ticket or poster
    /// scan, the archive's photo of the tape, and failing both, the scan
    /// from the nearest night — the same run or tour, nine times in ten.
    /// A page should never show a show with nothing on it.
    func cover(date: String?, identifier: String?, catalog: any ShowCatalog) async -> UIImage? {
        if catalog.isAvailable, let date,
           let night = await catalog.show(onDate: date),
           let coverURL = night.coverImageURL, let url = URL(string: coverURL),
           let scanned = await image(from: url) {
            return scanned
        }
        if let identifier, !identifier.isEmpty, !identifier.hasPrefix("placeholder-"),
           let photo = await thumbnail(for: identifier) {
            return photo
        }
        if catalog.isAvailable, let date {
            for borrowed in await catalog.nearestCovers(toDate: date, limit: 3) {
                if let url = URL(string: borrowed), let scan = await image(from: url) {
                    return scan
                }
            }
        }
        return nil
    }
}

extension Show {
    /// A minimal Show for artwork rendering when no recording is resolved
    /// yet (hero card before its lookup, curated canon cards).
    static func artworkPlaceholder(date: String, venue: String?, location: String? = nil) -> Show {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return Show(identifier: "placeholder-\(date)", title: venue ?? date,
                    date: formatter.date(from: date), dateString: date,
                    venue: venue, location: location, year: Int(date.prefix(4)),
                    avgRating: nil, numReviews: nil, downloads: nil, source: nil)
    }
}

/// Generated ticket-stub cover art, cached per show — the offline
/// fallback when the archive has no usable image.
@MainActor
enum StubArtwork {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for show: Show,
                      layout: NowPlayingCoordinator.StubLayout = .square) -> UIImage {
        let key = "\(show.identifier)|\(layout.rawValue)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = NowPlayingCoordinator.renderStubImage(
            dateText: show.displayDate,
            venueText: show.venue ?? "Grateful Dead",
            layout: layout)
        cache.setObject(image, forKey: key)
        return image
    }
}
