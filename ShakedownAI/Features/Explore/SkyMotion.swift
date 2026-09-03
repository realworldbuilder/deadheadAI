import CoreMotion
import SwiftUI
import UIKit

/// Device tilt for the Explore sky's parallax: roll and pitch relative to
/// however the phone was held when the sky appeared, smoothed and clamped
/// to -1…1. Nothing moves under Reduce Motion or when there's no motion
/// hardware (the simulator), so the sky just holds still.
@Observable
final class SkyMotion {
    private(set) var tilt: CGSize = .zero
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var reference: CMAttitude?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive,
              !UIAccessibility.isReduceMotionEnabled else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            MainActor.assumeIsolated {
                guard let attitude = motion?.attitude.copy() as? CMAttitude else { return }
                if let reference = self.reference {
                    attitude.multiply(byInverseOf: reference)
                } else {
                    self.reference = motion?.attitude.copy() as? CMAttitude
                    return
                }
                let x = max(-1, min(1, attitude.roll / 0.5))
                let y = max(-1, min(1, attitude.pitch / 0.5))
                // Low-pass so the sky glides rather than jitters.
                self.tilt = CGSize(width: self.tilt.width + (x - self.tilt.width) * 0.12,
                                   height: self.tilt.height + (y - self.tilt.height) * 0.12)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        reference = nil
        tilt = .zero
    }
}

/// A slow, tiny wander so nothing in the sky is nailed down. Direction,
/// distance, and period all come from the seed, so neighbours never move in
/// step. Holds still under Reduce Motion.
struct SkyDrift: ViewModifier {
    var seed: Int
    var amplitude: CGFloat = 5
    @State private var away = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let h = UInt64(bitPattern: Int64(seed + 1)) &* 0x9E37_79B9_7F4A_7C15
        let dx = amplitude * (CGFloat((h >> 8) % 100) / 50 - 1)
        let dy = amplitude * (CGFloat((h >> 24) % 100) / 50 - 1)
        let period = 7 + Double((h >> 40) % 60) / 10   // 7–13 s each way
        let moving = away && !reduceMotion
        content
            .offset(x: moving ? dx : 0, y: moving ? dy : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                    away = true
                }
            }
    }
}
