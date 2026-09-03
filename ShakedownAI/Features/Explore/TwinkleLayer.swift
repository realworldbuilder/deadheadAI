import SwiftUI

/// A handful of stars that breathe, and every so often one that falls.
/// `StarfieldBackground` is static on purpose, so this sits over it on
/// Explore alone and redraws a few dozen points at 20 fps. Under Reduce
/// Motion it draws once and holds, and nothing falls.
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
                    : tint > 0.72 ? Sky.denim
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
            if time > 0 {
                drawMeteor(in: &context, size: size, time: time)
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One streak per cycle, at an irregular moment within it, from a
    /// random spot in the upper sky, falling left or right. Under a second
    /// long; brightest in the middle of its fall.
    private func drawMeteor(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let period: TimeInterval = 14
        let duration: TimeInterval = 0.85
        let cycle = floor(time / period)
        var rng = LCG(seed: seed ^ (UInt64(cycle) &* 0x9E37))
        let delay = 3 + Double(rng.next()) * 8
        let t = time - cycle * period - delay
        guard t >= 0, t < duration else { return }
        let progress = t / duration

        let start = CGPoint(x: size.width * (0.15 + rng.next() * 0.7),
                            y: size.height * (0.04 + rng.next() * 0.3))
        let angle = (30 + Double(rng.next()) * 35) * .pi / 180
        let dir: CGFloat = rng.next() > 0.5 ? 1 : -1
        let travel: CGFloat = 200
        let head = CGPoint(x: start.x + dir * cos(angle) * travel * progress,
                           y: start.y + sin(angle) * travel * progress)
        let fade = sin(progress * .pi)
        let tailLength = 60 + 30 * fade
        let tail = CGPoint(x: head.x - dir * cos(angle) * tailLength,
                           y: head.y - sin(angle) * tailLength)

        var streak = Path()
        streak.move(to: tail)
        streak.addLine(to: head)
        context.stroke(streak,
                       with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.85 * fade)]),
                                             startPoint: tail, endPoint: head),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        let glow = CGRect(x: head.x - 4, y: head.y - 4, width: 8, height: 8)
        context.fill(Path(ellipseIn: glow), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.6 * fade), .clear]),
            center: head, startRadius: 0, endRadius: 4))
    }
}
