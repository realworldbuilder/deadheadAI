import SwiftUI

/// A handful of stars that breathe. `SpaceBackground` is static on purpose —
/// thirty screens share it — so this sits over it on Explore alone and
/// redraws a few dozen points at 20 fps. Under Reduce Motion it draws once
/// and holds.
struct TwinkleLayer: View {
    var count: Int = 18
    var seed: UInt64 = 0xC0FFEE
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            canvas(time: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                canvas(time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func canvas(time: TimeInterval) -> some View {
        Canvas { context, size in
            var rng = LCG(seed: seed)
            for _ in 0..<count {
                let x = rng.next() * size.width
                let y = rng.next() * size.height
                let r = 1.1 + rng.next() * 1.1
                let speed = 0.6 + Double(rng.next()) * 1.4
                let phase = Double(rng.next()) * 2 * .pi
                let tint = rng.next()
                let color: Color = tint > 0.85 ? Color(red: 1.0, green: 0.92, blue: 0.72)
                    : tint > 0.72 ? Theme.denim
                    : .white

                let breath = 0.5 + 0.5 * sin(time * speed + phase)
                let alpha = 0.35 + 0.65 * breath

                let halo = CGRect(x: x - r * 3, y: y - r * 3, width: r * 6, height: r * 6)
                context.fill(Path(ellipseIn: halo), with: .radialGradient(
                    Gradient(colors: [color.opacity(alpha * 0.35), .clear]),
                    center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 3))

                let core = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: core), with: .color(color.opacity(alpha)))
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
