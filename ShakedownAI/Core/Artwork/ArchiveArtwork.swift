import UIKit

/// Fetches archive.org's per-item tile image
/// (`archive.org/services/img/{identifier}`) — often a real photo or a
/// scanned ticket stub — and rejects the waveform screenshots many
/// transfers use as their thumbnail, so junk never becomes cover art.
/// Callers fall back to the generated ticket-stub artwork.
final class ArchiveArtwork {
    static let shared = ArchiveArtwork()

    private let cache = NSCache<NSString, UIImage>()
    /// Identifiers whose tile was missing or junk — don't re-fetch this run.
    private var misses = Set<String>()

    /// Fetch any remote cover (e.g. a jerrygarcia.com ticket-stub scan
    /// from the catalog). No waveform filter — these are curated scans.
    func image(from url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard !misses.contains(url.absoluteString),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data),
              image.size.width >= 50 else {
            misses.insert(url.absoluteString)
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }

    func thumbnail(for identifier: String) async -> UIImage? {
        if let hit = cache.object(forKey: identifier as NSString) { return hit }
        guard !misses.contains(identifier),
              let url = URL(string: "https://archive.org/services/img/\(identifier)") else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data),
              Self.looksLikeRealArt(image) else {
            misses.insert(identifier)
            return nil
        }
        cache.setObject(image, forKey: identifier as NSString)
        return image
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

/// Generated ticket-stub cover art, cached per show — the offline
/// fallback when the archive has no usable image.
@MainActor
enum StubArtwork {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for show: Show) -> UIImage {
        if let hit = cache.object(forKey: show.identifier as NSString) { return hit }
        let image = NowPlayingCoordinator.renderStubImage(
            dateText: show.displayDate,
            venueText: show.venue ?? "Grateful Dead")
        cache.setObject(image, forKey: show.identifier as NSString)
        return image
    }
}
