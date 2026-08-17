import AVFoundation
import Foundation

/// Configures the shared audio session for background playback and reacts to
/// interruptions (phone calls, other apps taking audio).
final class AudioSessionManager {
    private var activated = false
    private var interruptionObserver: (any NSObjectProtocol)?
    private var routeChangeObserver: (any NSObjectProtocol)?

    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEndedShouldResume: (() -> Void)?
    /// Fired when the active output route disappears (headphones unplugged,
    /// Bluetooth device disconnected) — the caller should pause.
    var onRouteDisconnected: (() -> Void)?

    /// Idempotent; called lazily on first play.
    func activate() {
        guard !activated else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            activated = true
        } catch {
            // Playback still works in-foreground without a configured session.
        }
        observeInterruptions()
        observeRouteChanges()
    }

    private func observeRouteChanges() {
        guard routeChangeObserver == nil else { return }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Pull Sendable scalars out before hopping to the main actor.
            let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, let reasonRaw,
                      AVAudioSession.RouteChangeReason(rawValue: reasonRaw) == .oldDeviceUnavailable
                else { return }
                self.onRouteDisconnected?()
            }
        }
    }

    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Pull Sendable scalars out before hopping to the main actor.
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                guard let self,
                      let typeRaw,
                      let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
                switch type {
                case .began:
                    self.onInterruptionBegan?()
                case .ended:
                    if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                        self.onInterruptionEndedShouldResume?()
                    }
                @unknown default:
                    break
                }
            }
        }
    }
}
