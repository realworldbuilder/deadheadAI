import SwiftUI

/// Deadhead AI design language: a temple ceiling painted with the night sky.
/// Deep indigo space behind everything, aged-gold accents like gilding on
/// stone, terracotta and lapis where the old palette ran red and blue, and
/// parchment-toned type. Egyptian funerary art by way of the space age —
/// the light is warm now, coming off gold leaf instead of an aurora.
enum Theme {

    // MARK: - Colors

    /// Deep space. The starfield and nebulae draw on top of this.
    static let background = Color.black
    /// Barely-lifted midnight indigo panel, like painted tomb plaster.
    static let surface = Color(red: 0.045, green: 0.045, blue: 0.088)
    /// Raised card surface, catching a little lamplight.
    static let surfaceRaised = Color(red: 0.080, green: 0.075, blue: 0.135)
    /// Thin gold-leaf wireframe strokes.
    static let stroke = Color(red: 0.83, green: 0.69, blue: 0.45).opacity(0.26)

    /// Aged temple gold. Primary accent — gilding, not glitter.
    static let accent = Color(red: 0.85, green: 0.69, blue: 0.42)
    /// Deep bronze for gradients and pressed states.
    static let accentDeep = Color(red: 0.45, green: 0.31, blue: 0.13)
    /// Terracotta rust, like the waves in the emblem. Links, alerts.
    static let rose = Color(red: 0.80, green: 0.33, blue: 0.15)
    /// Faience turquoise for SBD tags and cool highlights.
    static let sage = Color(red: 0.42, green: 0.80, blue: 0.72)
    /// Lapis lazuli for segues/links to songs.
    static let denim = Color(red: 0.48, green: 0.56, blue: 0.92)

    /// Warm parchment white, like papyrus catching lamplight.
    static let textPrimary = Color(red: 0.96, green: 0.92, blue: 0.83)
    /// Sandstone body copy — warm grey, not phosphor.
    static let textSecondary = Color(red: 0.74, green: 0.68, blue: 0.56)
    /// Dusty-limestone captions and metadata.
    static let textTertiary = Color(red: 0.52, green: 0.47, blue: 0.38)

    static let accentGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Translucent hull for hero surfaces, so the starfield reads through.
    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.09, blue: 0.17).opacity(0.82),
            Color(red: 0.045, green: 0.035, blue: 0.075).opacity(0.90),
            Color(red: 0.025, green: 0.018, blue: 0.045).opacity(0.86),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Ember wash for large surfaces that want depth behind them — the sun
    /// rising behind the mask in the emblem.
    static let nebulaGradient = RadialGradient(
        colors: [
            Color(red: 0.55, green: 0.28, blue: 0.08).opacity(0.42),
            Color(red: 0.16, green: 0.09, blue: 0.20).opacity(0.32),
            .clear,
        ],
        center: .center, startRadius: 0, endRadius: 260
    )

    /// Gold-leaf lettering, burnished top to bottom.
    static let chromeGradient = LinearGradient(
        colors: [
            Color(red: 0.99, green: 0.93, blue: 0.76),
            Color(red: 0.76, green: 0.58, blue: 0.32),
            Color(red: 0.95, green: 0.85, blue: 0.62),
            Color(red: 0.55, green: 0.40, blue: 0.19),
        ],
        startPoint: .top, endPoint: .bottom
    )

    /// Painted-tomb spectrum — gold, ember, rust, faience, lapis — used
    /// sparingly for special borders.
    static let cosmicGradient = AngularGradient(
        colors: [rose, Color(red: 0.93, green: 0.55, blue: 0.20), accent,
                 Color(red: 0.99, green: 0.90, blue: 0.65), sage, denim,
                 Color(red: 0.35, green: 0.22, blue: 0.55), rose],
        center: .center
    )

    // MARK: - Typography

    /// Big serif display, like the hand-inked logotype.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }

    /// Section titles.
    static let title = Font.system(.title2, design: .serif).weight(.semibold)
    static let headline = Font.system(.headline, design: .serif)
    /// Body reads like Times on a black page.
    static let body = Font.system(.body, design: .serif)
    static let caption = Font.system(.caption, design: .default)

    /// Monospaced, for dates and that starlit-instrument glow.
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Letter-spacing. Type in space should drift apart a little.
    static let titleTracking: CGFloat = 1.1
    static let capsTracking: CGFloat = 2.4

    // MARK: - Metrics

    static let cornerRadius: CGFloat = 20
    static let cardPadding: CGFloat = 20
    static let screenPadding: CGFloat = 24
    /// Gap between major sections on a screen.
    static let sectionSpacing: CGFloat = 28
    /// Gap between sibling cards inside a section.
    static let itemSpacing: CGFloat = 14
    /// Leading between stacked lines of body copy.
    static let lineSpacing: CGFloat = 3
}

// MARK: - Reusable modifiers

struct CardBackground: ViewModifier {
    var raised = false
    func body(content: Content) -> some View {
        content
            .background(raised ? Theme.surfaceRaised.opacity(0.72) : Theme.surface.opacity(0.66))
            .background(.ultraThinMaterial.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.stroke, Theme.stroke.opacity(0.25)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    func cardStyle(raised: Bool = false) -> some View {
        modifier(CardBackground(raised: raised))
    }

    /// Section header used across feature screens.
    func sectionHeaderStyle() -> some View {
        font(Theme.title)
            .tracking(Theme.titleTracking)
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Widely-tracked small caps, for labels that should read as signage.
    func spacedCaps() -> some View {
        font(Theme.mono(11, weight: .semibold))
            .tracking(Theme.capsTracking)
            .textCase(.uppercase)
    }

    /// Gold-leaf wordmark treatment.
    func chromeText() -> some View {
        foregroundStyle(Theme.chromeGradient)
            .tracking(Theme.titleTracking)
            .shadow(color: Color(red: 1.0, green: 0.85, blue: 0.55).opacity(0.35), radius: 1, y: 0.5)
    }
}
