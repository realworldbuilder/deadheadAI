import SwiftUI

/// TapeTree design language: a tape trader's den after dark — walnut
/// shelving and lamplight, cream Maxell labels, ferric-oxide rust and
/// forest green where the old palette ran gold and lapis. The light is
/// still warm, but now it comes off a VU meter instead of gold leaf.
enum Theme {

    // MARK: - Colors

    /// The dark of the den. Backdrop haze and dust draw on top of this.
    static let background = Color.black
    /// Barely-lifted espresso panel, like a shelf in shadow.
    static let surface = Color(red: 0.078, green: 0.058, blue: 0.040)
    /// Raised walnut card surface, catching a little lamplight.
    static let surfaceRaised = Color(red: 0.125, green: 0.094, blue: 0.066)
    /// Thin cream tape-label strokes.
    static let stroke = Color(red: 0.85, green: 0.76, blue: 0.60).opacity(0.26)

    /// Ferric-oxide rust-amber. Primary accent — tape coating, not glitter.
    static let accent = Color(red: 0.86, green: 0.50, blue: 0.24)
    /// Deep oxide for gradients and pressed states.
    static let accentDeep = Color(red: 0.44, green: 0.21, blue: 0.09)
    /// Red rust, a shade redder than the accent. Links, alerts.
    static let rose = Color(red: 0.76, green: 0.25, blue: 0.14)
    /// Forest-leaf green for SBD tags and cool highlights.
    static let sage = Color(red: 0.44, green: 0.72, blue: 0.42)
    /// Faded workshirt denim for segues/links to songs.
    static let denim = Color(red: 0.52, green: 0.62, blue: 0.78)

    /// Cream label white, like a J-card catching lamplight.
    static let textPrimary = Color(red: 0.96, green: 0.92, blue: 0.80)
    /// Warm oat body copy — warm grey, not phosphor.
    static let textSecondary = Color(red: 0.76, green: 0.69, blue: 0.55)
    /// Dusty-kraft captions and metadata.
    static let textTertiary = Color(red: 0.54, green: 0.47, blue: 0.36)

    static let accentGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Translucent hull for hero surfaces, so the backdrop reads through.
    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.14, green: 0.10, blue: 0.065).opacity(0.82),
            Color(red: 0.082, green: 0.058, blue: 0.038).opacity(0.90),
            Color(red: 0.045, green: 0.030, blue: 0.020).opacity(0.86),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Oxide wash for large surfaces that want depth behind them — lamplight
    /// pooling on a reel of tape.
    static let nebulaGradient = RadialGradient(
        colors: [
            Color(red: 0.50, green: 0.24, blue: 0.08).opacity(0.42),
            Color(red: 0.20, green: 0.11, blue: 0.06).opacity(0.32),
            .clear,
        ],
        center: .center, startRadius: 0, endRadius: 260
    )

    /// Burnished cream-brass lettering, top to bottom.
    static let chromeGradient = LinearGradient(
        colors: [
            Color(red: 0.99, green: 0.95, blue: 0.84),
            Color(red: 0.80, green: 0.70, blue: 0.53),
            Color(red: 0.95, green: 0.89, blue: 0.74),
            Color(red: 0.56, green: 0.45, blue: 0.30),
        ],
        startPoint: .top, endPoint: .bottom
    )

    /// Analog spectrum — rust, amber, cream, leaf, denim, walnut — used
    /// sparingly for special borders.
    static let cosmicGradient = AngularGradient(
        colors: [rose, Color(red: 0.90, green: 0.52, blue: 0.18), accent,
                 Color(red: 0.98, green: 0.92, blue: 0.72), sage, denim,
                 Color(red: 0.30, green: 0.18, blue: 0.10), rose],
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

    /// Cream-brass wordmark treatment.
    func chromeText() -> some View {
        foregroundStyle(Theme.chromeGradient)
            .tracking(Theme.titleTracking)
            .shadow(color: Color(red: 1.0, green: 0.94, blue: 0.78).opacity(0.30), radius: 1, y: 0.5)
    }
}
