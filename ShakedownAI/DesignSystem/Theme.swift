import SwiftUI
import UIKit

/// Nethead design language: a baseline, near-monochrome system. Neutral
/// surfaces that follow the appearance setting, one sans typeface set in
/// Dynamic Type styles, hairline dividers instead of boxes, and black-on-
/// white (or white-on-charcoal) for every control. The icon's colours
/// survive only as small highlights: the bolt's red for progress, play
/// buttons and what's playing now, leaf green for a soundboard tag, the
/// bolt's blue for a segue mark. Real ticket and poster scans are the only
/// decoration.
enum Theme {

    // MARK: - Colors

    /// Page background. White by day, ChatGPT's warm charcoal at night.
    static let background = Color(light: rgb(1.00, 1.00, 1.00), dark: rgb(0.129, 0.129, 0.129))
    /// Flat card / bar surface, one step off the page.
    static let surface = Color(light: rgb(0.976, 0.976, 0.976), dark: rgb(0.184, 0.184, 0.184))
    /// Selected rows, chips, and the user's chat bubble.
    static let surfaceRaised = Color(light: rgb(0.937, 0.937, 0.937), dark: rgb(0.220, 0.220, 0.220))
    /// Hairline dividers and card borders. Opaque, so it never muddies.
    static let stroke = Color(light: rgb(0.925, 0.925, 0.925), dark: rgb(0.259, 0.259, 0.259))

    /// The bolt's red. Deepened by day so it holds contrast on white.
    static let accent = Color(light: rgb(0.80, 0.13, 0.11), dark: rgb(0.93, 0.29, 0.25))
    /// Text and glyphs drawn on a flat accent fill.
    static let onAccent = Color(light: rgb(1, 1, 1), dark: rgb(1, 1, 1))
    /// Crimson for errors and destructive actions — a step darker than the accent.
    static let rose = Color(light: rgb(0.66, 0.10, 0.16), dark: rgb(0.88, 0.38, 0.42))
    /// Leaf green for soundboard tags and success states.
    static let sage = Color(light: rgb(0.16, 0.52, 0.24), dark: rgb(0.40, 0.74, 0.42))
    /// The bolt's blue for segues, audience tags, and song links.
    static let denim = Color(light: rgb(0.12, 0.36, 0.84), dark: rgb(0.44, 0.62, 1.00))

    static let textPrimary = Color(light: rgb(0.051, 0.051, 0.051), dark: rgb(0.925, 0.925, 0.925))
    static let textSecondary = Color(light: rgb(0.365, 0.365, 0.365), dark: rgb(0.706, 0.706, 0.706))
    static let textTertiary = Color(light: rgb(0.459, 0.459, 0.459), dark: rgb(0.557, 0.557, 0.557))

    /// The accent as a dynamic UIColor, for UIKit views (AirPlay picker).
    static let accentUIColor = UIColor(light: rgb(0.80, 0.13, 0.11), dark: rgb(0.93, 0.29, 0.25))

    // MARK: - Typography

    static let largeTitle = Font.largeTitle.weight(.semibold)
    /// Section titles.
    static let title = Font.title3.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let subheadline = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
    /// Player timecodes: tabular digits, the only place figures must line up.
    static let timecode = Font.footnote.monospacedDigit()

    // MARK: - Metrics

    static let cornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let screenPadding: CGFloat = 16
    /// Gap between major sections on a screen.
    static let sectionSpacing: CGFloat = 24
    /// Gap between sibling cards inside a section.
    static let itemSpacing: CGFloat = 12
    /// Leading between stacked lines of body copy.
    static let lineSpacing: CGFloat = 2
}

// MARK: - Adaptive colour helpers

private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
    UIColor(red: r, green: g, blue: b, alpha: 1)
}

private extension UIColor {
    convenience init(light: UIColor, dark: UIColor) {
        self.init { $0.userInterfaceStyle == .dark ? dark : light }
    }
}

private extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor(light: light, dark: dark))
    }
}

// MARK: - Reusable modifiers

struct CardBackground: ViewModifier {
    var raised = false
    var bordered = true
    func body(content: Content) -> some View {
        content
            .background(raised ? Theme.surfaceRaised : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                }
            }
    }
}

/// A half-point rule in the stroke colour.
struct HairlineDivider: View {
    var body: some View {
        Rectangle().fill(Theme.stroke).frame(height: 0.5)
    }
}

/// The app mark: the Nethead skeleton at its terminal, as transparent art
/// so it sits directly on whatever surface is behind it — no tile, no clip.
struct AppMark: View {
    var size: CGFloat = 28
    var body: some View {
        Image("NowPlayingMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension View {
    func cardStyle(raised: Bool = false, bordered: Bool = true) -> some View {
        modifier(CardBackground(raised: raised, bordered: bordered))
    }

    /// Section header used across feature screens.
    func sectionHeaderStyle() -> some View {
        font(Theme.title)
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Small sentence-case label above a section or field.
    func eyebrowStyle() -> some View {
        font(Theme.footnote.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
    }

    /// Stacked row: full width, breathing room, hairline below.
    func listRowStyle(divider: Bool = true) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                if divider { HairlineDivider() }
            }
    }
}

// MARK: - Button styles

/// The one filled button: ink capsule, page-coloured label — black on white
/// by day, white on charcoal by night.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Capsule().fill(Theme.textPrimary))
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : 0.45))
    }
}

/// Quiet text button for secondary actions beside a primary one.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.subheadline.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.45))
    }
}

/// Outlined capsule for suggestion chips.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.subheadline)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(configuration.isPressed ? Theme.surfaceRaised : .clear))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func primary(fullWidth: Bool) -> PrimaryButtonStyle { PrimaryButtonStyle(fullWidth: fullWidth) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == ChipButtonStyle {
    static var chip: ChipButtonStyle { ChipButtonStyle() }
}

// MARK: - Appearance

/// The reader's choice of light or dark, persisted under `appearance`.
/// Dark is the default — the den after dark — and `.system` follows the
/// device for anyone who'd rather it did.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static let storageKey = "appearance"
}
