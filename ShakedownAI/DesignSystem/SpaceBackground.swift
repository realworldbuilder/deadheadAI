import SwiftUI

/// Deep space behind every screen: a midnight-indigo sky with warm nebula
/// haze, an ember sunrise glowing low like the sun behind the emblem's mask,
/// and a starfield laid out in three planes of depth so the view reads as
/// distance rather than as a flat dot pattern. Deterministic — the same stars
/// sit in the same places every launch, and nothing animates, so this stays
/// cheap on the ~30 screens that use it.
struct SpaceBackground: View {
    var body: some View {
        ZStack {
            // Void, lifted very slightly toward warm indigo at the center so
            // the screen has a middle rather than a wall.
            RadialGradient(
                colors: [Color(red: 0.055, green: 0.045, blue: 0.10), .black],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 0, endRadius: 620
            )
            .background(Color.black)

            nebulae
            galacticBand
            sunrise

            Canvas { context, size in
                var rng = LCG(seed: 0x5EED)
                let area = size.width * size.height

                // Far plane: dense, dim, sub-pixel dust.
                drawStars(&rng, in: context, size: size,
                          count: max(Int(area / 1100), 220),
                          radius: 0.35...0.75, alpha: 0.10...0.34, glow: false)

                // Mid plane.
                drawStars(&rng, in: context, size: size,
                          count: max(Int(area / 5200), 70),
                          radius: 0.7...1.25, alpha: 0.30...0.70, glow: false)

                // Near plane: few, bright, haloed.
                drawStars(&rng, in: context, size: size,
                          count: max(Int(area / 26000), 14),
                          radius: 1.3...2.2, alpha: 0.75...1.0, glow: true)
            }
            .allowsHitTesting(false)
            .blendMode(.screen)
        }
        .ignoresSafeArea()
    }

    // MARK: - Nebulae

    /// Three soft clouds of gas. Heavily blurred, low opacity — they should
    /// register as depth, never as shapes you could point at. Lapis overhead,
    /// old gold at the horizon line, rust below — the emblem's own strata.
    private var nebulae: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                cloud(Color(red: 0.22, green: 0.26, blue: 0.68), opacity: 0.30)
                    .frame(width: w * 1.15, height: w * 1.15)
                    .position(x: w * 0.20, y: h * 0.18)
                cloud(Color(red: 0.55, green: 0.38, blue: 0.10), opacity: 0.20)
                    .frame(width: w * 1.0, height: w * 1.0)
                    .position(x: w * 0.92, y: h * 0.44)
                cloud(Color(red: 0.55, green: 0.20, blue: 0.06), opacity: 0.18)
                    .frame(width: w * 0.9, height: w * 0.9)
                    .position(x: w * 0.38, y: h * 0.86)
            }
            .blur(radius: 46)
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }

    private func cloud(_ color: Color, opacity: Double) -> some View {
        Ellipse()
            .fill(
                RadialGradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.35), .clear],
                               center: .center, startRadius: 0, endRadius: 240)
            )
    }

    /// The dusty lane of a galaxy cutting across the sky on a diagonal,
    /// tinted like gold dust.
    private var galacticBand: some View {
        GeometryReader { proxy in
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [.clear,
                                 Color(red: 0.88, green: 0.76, blue: 0.52).opacity(0.11),
                                 Color(red: 0.98, green: 0.92, blue: 0.76).opacity(0.05),
                                 .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: proxy.size.height * 1.5, height: proxy.size.width * 0.62)
                .blur(radius: 34)
                .rotationEffect(.degrees(-62))
                .position(x: proxy.size.width * 0.62, y: proxy.size.height * 0.5)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// The emblem's sunrise: an ember glow low on the screen with faint
    /// concentric gold rings radiating from it, like the lines cut around
    /// the sun on the mask's brow. Static, so it costs one draw.
    private var sunrise: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let center = CGPoint(x: w * 0.5, y: h * 1.06)
            ZStack {
                // Ember core, mostly below the bottom edge.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(red: 0.95, green: 0.55, blue: 0.18).opacity(0.30),
                                     Color(red: 0.70, green: 0.30, blue: 0.08).opacity(0.14),
                                     .clear],
                            center: .center, startRadius: 0, endRadius: w * 0.55
                        )
                    )
                    .frame(width: w * 1.1, height: w * 1.1)
                    .position(center)

                // Radiating rings, fading with distance.
                Canvas { context, _ in
                    for i in 1...7 {
                        let r = w * 0.14 * CGFloat(i)
                        let alpha = 0.085 * (1.0 - Double(i) / 8.5)
                        let rect = CGRect(x: center.x - r, y: center.y - r,
                                          width: r * 2, height: r * 2)
                        context.stroke(
                            Path(ellipseIn: rect),
                            with: .color(Color(red: 0.88, green: 0.70, blue: 0.42).opacity(alpha)),
                            lineWidth: 1
                        )
                    }
                }
            }
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Starfield

    private func drawStars(_ rng: inout LCG, in context: GraphicsContext, size: CGSize,
                           count: Int, radius: ClosedRange<CGFloat>,
                           alpha: ClosedRange<Double>, glow: Bool) {
        for _ in 0..<count {
            let x = rng.next() * size.width
            let y = rng.next() * size.height
            let r = radius.lowerBound + rng.next() * (radius.upperBound - radius.lowerBound)
            let a = alpha.lowerBound + Double(rng.next()) * (alpha.upperBound - alpha.lowerBound)

            // Most stars are white; a scattering carry a stellar tint.
            let tint = rng.next()
            let color: Color
            if tint > 0.965 { color = Theme.rose }
            else if tint > 0.925 { color = Theme.sage }
            else if tint > 0.895 { color = Color(red: 1.0, green: 0.85, blue: 0.55) }
            else if tint > 0.865 { color = Theme.denim }
            else { color = .white }

            if glow {
                // Halo, then core, then a faint diffraction cross.
                let halo = CGRect(x: x - r * 3.4, y: y - r * 3.4, width: r * 6.8, height: r * 6.8)
                context.fill(Path(ellipseIn: halo), with: .radialGradient(
                    Gradient(colors: [color.opacity(a * 0.42), .clear]),
                    center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r * 3.4))

                let spike = r * 4.6
                var cross = Path()
                cross.move(to: CGPoint(x: x - spike, y: y))
                cross.addLine(to: CGPoint(x: x + spike, y: y))
                cross.move(to: CGPoint(x: x, y: y - spike))
                cross.addLine(to: CGPoint(x: x, y: y + spike))
                context.stroke(cross, with: .color(color.opacity(a * 0.22)), lineWidth: 0.6)
            }

            let core = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: core), with: .color(color.opacity(a)))
        }
    }

    /// Tiny deterministic pseudo-random generator (stable star placement).
    private struct LCG {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) % 10_000) / 10_000
        }
    }
}

/// A procedural planet, like the celestial nav buttons on the 1996 home page.
struct PlanetView: View {
    enum Style: CaseIterable {
        case marbled      // swirled gas giant
        case ringed       // saturn with a tilted ring
        case earthlike    // blue-green
        case comet        // bright core with a tail
        case galaxy       // spiral smudge
        case sun          // hot yellow-orange
        case spiral       // barred spiral, arms and all
        case nebula       // a torn blue cloud with stars caught in it
        case redGiant     // hot red annulus, burning at the rim
        case starburst    // electric-blue streaks from a common origin
        case wireGlobe    // a meshed sphere, latitude and longitude
    }

    var style: Style
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            switch style {
            case .marbled:
                sphere(colors: [Theme.rose, Color(red: 0.45, green: 0.05, blue: 0.25), .black])
            case .ringed:
                sphere(colors: [Color.yellow, Color(red: 0.65, green: 0.35, blue: 0.1), .black])
                ring
            case .earthlike:
                sphere(colors: [Theme.sage, Color(red: 0.05, green: 0.25, blue: 0.55), .black])
            case .comet:
                cometBody
            case .galaxy:
                galaxyBody
            case .sun:
                sphere(colors: [.white, .yellow, Color(red: 0.9, green: 0.45, blue: 0.05)])
                    .shadow(color: .yellow.opacity(0.6), radius: size * 0.18)
            case .spiral:
                spiralBody
            case .nebula:
                nebulaBody
            case .redGiant:
                redGiantBody
            case .starburst:
                starburstBody
            case .wireGlobe:
                wireGlobeBody
            }
        }
        .frame(width: size, height: size)
    }

    private func sphere(colors: [Color]) -> some View {
        Circle()
            .fill(
                RadialGradient(colors: colors,
                               center: UnitPoint(x: 0.35, y: 0.3),
                               startRadius: 0, endRadius: size * 0.62)
            )
    }

    private var ring: some View {
        Ellipse()
            .strokeBorder(
                LinearGradient(colors: [.white.opacity(0.9), Theme.textTertiary],
                               startPoint: .leading, endPoint: .trailing),
                lineWidth: max(size * 0.045, 1.5)
            )
            .frame(width: size * 1.45, height: size * 0.5)
            .rotationEffect(.degrees(-18))
    }

    private var cometBody: some View {
        ZStack {
            // Tail
            Path { path in
                path.move(to: CGPoint(x: size * 0.55, y: size * 0.45))
                path.addLine(to: CGPoint(x: size * 1.05, y: -size * 0.1))
                path.addLine(to: CGPoint(x: size * 0.75, y: size * 0.6))
                path.closeSubpath()
            }
            .fill(LinearGradient(colors: [Theme.sage.opacity(0.7), .clear],
                                 startPoint: .bottomLeading, endPoint: .topTrailing))
            Circle()
                .fill(RadialGradient(colors: [.white, Theme.sage, .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.3))
                .frame(width: size * 0.55, height: size * 0.55)
                .offset(x: -size * 0.08, y: size * 0.1)
        }
    }

    private var galaxyBody: some View {
        ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.9),
                                              Color(red: 0.55, green: 0.45, blue: 0.9).opacity(0.55),
                                              .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.5))
                .frame(width: size, height: size * 0.62)
                .rotationEffect(.degrees(-25))
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: size * 0.14, height: size * 0.14)
        }
    }

    /// A barred spiral seen face-on: arms swept out of stacked ellipses,
    /// each one rotated a little further and dimmer than the last.
    private var spiralBody: some View {
        ZStack {
            ForEach(0..<11, id: \.self) { i in
                let t = CGFloat(i) / 11
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.72, green: 0.78, blue: 1.0).opacity(0.62 * (1 - t) + 0.08),
                                     Color(red: 0.80, green: 0.55, blue: 1.0).opacity(0.26 * (1 - t))],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: size * (0.98 - t * 0.52), height: size * (0.30 - t * 0.19))
                    .rotationEffect(.degrees(Double(t) * 175))
            }
            .blur(radius: size * 0.018)

            Circle()
                .fill(RadialGradient(colors: [.white,
                                              Color(red: 1.0, green: 0.92, blue: 0.75).opacity(0.85),
                                              .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.19))
                .frame(width: size * 0.42, height: size * 0.42)
        }
        .rotationEffect(.degrees(-20))
    }

    /// A torn cloud of gas with a few stars burning through it.
    private var nebulaBody: some View {
        ZStack {
            wisp(Color(red: 0.20, green: 0.45, blue: 1.0), opacity: 0.60)
                .frame(width: size, height: size * 0.72)
                .rotationEffect(.degrees(-18))
            wisp(Color(red: 0.55, green: 0.30, blue: 0.95), opacity: 0.45)
                .frame(width: size * 0.78, height: size * 0.60)
                .offset(x: size * 0.12, y: -size * 0.10)
                .rotationEffect(.degrees(26))
            wisp(Color(red: 0.30, green: 0.85, blue: 1.0), opacity: 0.32)
                .frame(width: size * 0.56, height: size * 0.44)
                .offset(x: -size * 0.16, y: size * 0.12)

            // Stars caught inside the cloud.
            ForEach(0..<4, id: \.self) { i in
                let angle = Double(i) * 97.0
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: size * (i == 0 ? 0.09 : 0.05))
                    .offset(x: size * 0.26 * CGFloat(cos(angle)),
                            y: size * 0.20 * CGFloat(sin(angle)))
                    .shadow(color: .white.opacity(0.8), radius: size * 0.06)
            }
        }
        .blur(radius: size * 0.012)
    }

    private func wisp(_ color: Color, opacity: Double) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.3), .clear],
                                 center: .center, startRadius: 0, endRadius: size * 0.42))
            .blur(radius: size * 0.07)
    }

    /// A red giant burning at the rim — bright annulus, dark centre.
    private var redGiantBody: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [.clear,
                             Color(red: 0.35, green: 0.0, blue: 0.02).opacity(0.8),
                             Color(red: 1.0, green: 0.18, blue: 0.05),
                             Color(red: 1.0, green: 0.55, blue: 0.20).opacity(0.55),
                             .clear],
                    center: .center, startRadius: 0, endRadius: size * 0.52))
            Circle()
                .strokeBorder(Color(red: 1.0, green: 0.75, blue: 0.45).opacity(0.9),
                              lineWidth: size * 0.03)
                .frame(width: size * 0.62, height: size * 0.62)
                .blur(radius: size * 0.02)
        }
        .shadow(color: Color(red: 1.0, green: 0.15, blue: 0.05).opacity(0.55), radius: size * 0.16)
    }

    /// Electric-blue streaks thrown from a common origin.
    private var starburstBody: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                let t = CGFloat(i) / 7
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.55, green: 0.85, blue: 1.0),
                                 Color(red: 0.10, green: 0.35, blue: 1.0).opacity(0.15)],
                        startPoint: .bottom, endPoint: .top))
                    .frame(width: size * 0.045, height: size * (0.55 + t * 0.42))
                    .offset(y: -size * (0.22 + t * 0.16))
                    .rotationEffect(.degrees(Double(i) * 19 - 54))
            }
            Circle()
                .fill(RadialGradient(colors: [.white, Color(red: 0.4, green: 0.7, blue: 1.0), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.22))
                .frame(width: size * 0.36, height: size * 0.36)
        }
        .shadow(color: Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.6), radius: size * 0.12)
    }

    /// A meshed sphere — latitude and longitude drawn in thin phosphor.
    private var wireGlobeBody: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.22), .black.opacity(0.85)],
                                     center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 0, endRadius: size * 0.6))
            // Longitudes.
            ForEach(0..<4, id: \.self) { i in
                Ellipse()
                    .strokeBorder(Theme.accent.opacity(0.55), lineWidth: max(size * 0.014, 0.6))
                    .frame(width: size * (1.0 - CGFloat(i) * 0.28), height: size)
            }
            // Latitudes.
            ForEach(0..<3, id: \.self) { i in
                Ellipse()
                    .strokeBorder(Theme.accent.opacity(0.4), lineWidth: max(size * 0.012, 0.5))
                    .frame(width: size * (0.99 - CGFloat(i) * 0.22),
                           height: size * (0.30 + CGFloat(i) * 0.001))
                    .offset(y: size * (CGFloat(i) - 1) * 0.26)
            }
            Circle()
                .strokeBorder(Theme.accent.opacity(0.75), lineWidth: max(size * 0.016, 0.7))
        }
        .shadow(color: Theme.accent.opacity(0.4), radius: size * 0.1)
    }
}

/// A slow-spinning tie-dye spiral: our original nod to the psychedelic
/// centerpiece of the old site (no trademarked art).
struct SpiralMandala: View {
    var size: CGFloat = 120
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.cosmicGradient)
                .blur(radius: size * 0.04)
                .rotationEffect(.degrees(spin ? 360 : 0))
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .strokeBorder(Color.black.opacity(0.55), lineWidth: size * 0.02)
                    .frame(width: size * (1 - CGFloat(i) * 0.18),
                           height: size * (1 - CGFloat(i) * 0.18))
            }
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.34, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        // The animation is started inside `withAnimation` rather than declared
        // as `.animation(_:value:)`, which would also capture this view's first
        // placement and send it drifting across the screen for 24 seconds.
        .onAppear {
            guard !spin else { return }
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }
}
