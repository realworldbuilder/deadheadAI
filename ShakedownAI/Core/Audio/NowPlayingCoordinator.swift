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

    private static func renderStubImage(dateText: String, venueText: String) -> UIImage {
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Deep space with a scatter of stars, like the 1996 home page.
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            var seed: UInt64 = 0x5EED
            func rand() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) % 10_000) / 10_000
            }
            for _ in 0..<90 {
                let alpha = 0.35 + 0.6 * rand()
                UIColor(white: 1, alpha: alpha).setFill()
                let r = rand() > 0.85 ? 2.2 : 1.3
                ctx.cgContext.fillEllipse(in: CGRect(x: rand() * size.width,
                                                     y: rand() * size.height,
                                                     width: r, height: r))
            }
            let amber = UIColor(red: 0.90, green: 0.73, blue: 0.44, alpha: 1)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            ("GRATEFUL DEAD" as NSString).draw(
                in: CGRect(x: 20, y: 180, width: 560, height: 60),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 40, weight: .bold),
                    .foregroundColor: amber,
                    .paragraphStyle: paragraph,
                ])
            (dateText as NSString).draw(
                in: CGRect(x: 20, y: 280, width: 560, height: 50),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 30, weight: .medium),
                    .foregroundColor: UIColor(white: 0.92, alpha: 1),
                    .paragraphStyle: paragraph,
                ])
            (venueText as NSString).draw(
                in: CGRect(x: 40, y: 350, width: 520, height: 80),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 22, weight: .regular),
                    .foregroundColor: UIColor(white: 0.7, alpha: 1),
                    .paragraphStyle: paragraph,
                ])
        }
    }
}
