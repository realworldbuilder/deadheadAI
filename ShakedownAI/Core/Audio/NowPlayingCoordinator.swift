import Foundation
import MediaPlayer
import UIKit

/// Publishes lock-screen / control-center now-playing info and handles
/// remote commands (headphones, lock screen, CarPlay).
final class NowPlayingCoordinator {
    private weak var engine: PlayerEngine?
    private var artworkCache: (key: String, artwork: MPMediaItemArtwork)?

    init(engine: PlayerEngine) {
        self.engine = engine
        registerCommands()
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.engine?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.engine?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.engine?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.engine?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.engine?.previous() }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let engine = self?.engine else { return }
                engine.seek(to: max(0, engine.elapsed - 15))
            }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let engine = self?.engine else { return }
                engine.seek(to: min(engine.duration > 0 ? engine.duration : .infinity, engine.elapsed + 15))
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            let seconds = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
            Task { @MainActor [weak self] in
                if let seconds { self?.engine?.seek(to: seconds) }
            }
            return .success
        }
    }

    func refresh() {
        guard let engine, let show = engine.currentShow, let track = engine.currentTrack else {
            clear()
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: "Grateful Dead",
            MPMediaItemPropertyAlbumTitle: "\(show.displayDate) — \(show.venue ?? "Live")",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: engine.elapsed,
            MPMediaItemPropertyPlaybackDuration: engine.duration,
            MPNowPlayingInfoPropertyPlaybackRate: engine.isPlaying ? 1.0 : 0.0,
        ]
        info[MPMediaItemPropertyArtwork] = artwork(for: show)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Ticket-stub style generated artwork, cached per show.
    private func artwork(for show: Show) -> MPMediaItemArtwork {
        if let artworkCache, artworkCache.key == show.identifier {
            return artworkCache.artwork
        }
        let image = Self.renderStubImage(dateText: show.displayDate, venueText: show.venue ?? "Grateful Dead")
        // MediaPlayer invokes this handler on its own queue — it must not be
        // MainActor-isolated (the module default), or the executor check traps.
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
        artworkCache = (show.identifier, artwork)
        return artwork
    }

    /// How the generated stub is composed. `.square` is the lock-screen /
    /// square-card layout; `.wide` re-lays the same pieces for 3:2 cards
    /// (medallion left, lettering right); `.banner` is `.wide` without
    /// lettering, for cards that draw their own type over a scrim.
    enum StubLayout: String, Sendable {
        case square, wide, banner

        var size: CGSize {
            switch self {
            case .square: CGSize(width: 600, height: 600)
            case .wide, .banner: CGSize(width: 900, height: 600)
            }
        }
    }

    private static let stubAmber = UIColor(red: 0.90, green: 0.73, blue: 0.44, alpha: 1)

    static func renderStubImage(dateText: String, venueText: String,
                                layout: StubLayout = .square) -> UIImage {
        let size = layout.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            drawStubSpace(in: ctx, size: size)
            switch layout {
            case .square:
                drawStubMark(in: ctx, center: CGPoint(x: 300, y: 218), diameter: 320)
                drawStubLettering(in: ctx, dateText: dateText, venueText: venueText,
                                  alignment: .center,
                                  titleRect: CGRect(x: 20, y: 408, width: 560, height: 40),
                                  dateRect: CGRect(x: 20, y: 456, width: 560, height: 46),
                                  venueRect: CGRect(x: 40, y: 512, width: 520, height: 60),
                                  titleSize: 26, dateSize: 32, venueSize: 21)
            case .wide:
                // Ticket-stub proportions: the medallion fills the left
                // third, the lettering sits left-aligned beside it in the
                // upper-middle band, leaving the bottom clear for a card's
                // own pill overlay.
                drawStubMark(in: ctx, center: CGPoint(x: 250, y: 300), diameter: 360)
                drawStubLettering(in: ctx, dateText: dateText, venueText: venueText,
                                  alignment: .left,
                                  titleRect: CGRect(x: 470, y: 190, width: 390, height: 36),
                                  dateRect: CGRect(x: 470, y: 232, width: 390, height: 56),
                                  venueRect: CGRect(x: 470, y: 296, width: 390, height: 64),
                                  titleSize: 24, dateSize: 40, venueSize: 22)
            case .banner:
                drawStubMark(in: ctx, center: CGPoint(x: 330, y: 300), diameter: 380)
            }
        }
    }

    /// Deep space with a scatter of stars, like the 1996 home page.
    private static func drawStubSpace(in ctx: UIGraphicsImageRendererContext, size: CGSize) {
        UIColor(red: 0.05, green: 0.04, blue: 0.11, alpha: 1).setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        var seed: UInt64 = 0x5EED
        func rand() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) % 10_000) / 10_000
        }
        // Keep the star density constant as the canvas widens.
        let count = Int(90 * (size.width * size.height) / (600 * 600))
        for _ in 0..<count {
            let alpha = 0.35 + 0.6 * rand()
            UIColor(white: 1, alpha: alpha).setFill()
            let r = rand() > 0.85 ? 2.2 : 1.3
            ctx.cgContext.fillEllipse(in: CGRect(x: rand() * size.width,
                                                 y: rand() * size.height,
                                                 width: r, height: r))
        }
    }

    /// The mask, glowing amber. Clipped to a circle so the icon tile's
    /// square corners never show.
    private static func drawStubMark(in ctx: UIGraphicsImageRendererContext,
                                     center: CGPoint, diameter: CGFloat) {
        guard let mark = UIImage(named: "NowPlayingMark") else { return }
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [stubAmber.withAlphaComponent(0.28).cgColor,
                                       UIColor.clear.cgColor] as CFArray,
                              locations: [0, 1])
        if let glow {
            ctx.cgContext.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                                             endCenter: center, endRadius: diameter * 0.75,
                                             options: [])
        }
        let markRect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                              width: diameter, height: diameter)
        ctx.cgContext.saveGState()
        let inset = diameter * 24 / 320
        ctx.cgContext.addEllipse(in: markRect.insetBy(dx: inset, dy: inset))
        ctx.cgContext.clip()
        mark.draw(in: markRect)
        ctx.cgContext.restoreGState()
    }

    private static func drawStubLettering(in ctx: UIGraphicsImageRendererContext,
                                          dateText: String, venueText: String,
                                          alignment: NSTextAlignment,
                                          titleRect: CGRect, dateRect: CGRect, venueRect: CGRect,
                                          titleSize: CGFloat, dateSize: CGFloat, venueSize: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment

        ("GRATEFUL DEAD" as NSString).draw(
            in: titleRect,
            withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: titleSize, weight: .bold),
                .foregroundColor: stubAmber,
                .paragraphStyle: paragraph,
                .kern: 3,
            ])
        (dateText as NSString).draw(
            in: dateRect,
            withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: dateSize, weight: .medium),
                .foregroundColor: UIColor(white: 0.94, alpha: 1),
                .paragraphStyle: paragraph,
            ])
        (venueText as NSString).draw(
            in: venueRect,
            withAttributes: [
                .font: UIFont.systemFont(ofSize: venueSize, weight: .regular),
                .foregroundColor: UIColor(white: 0.72, alpha: 1),
                .paragraphStyle: paragraph,
            ])
    }
}
