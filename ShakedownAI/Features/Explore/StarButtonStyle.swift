import SwiftUI

/// Press feedback for a body in the Explore sky: a small dip in scale, a
/// brighter halo, and a light tap of haptic on the way down. Under Reduce
/// Motion only the halo changes.
struct StarButtonStyle: ButtonStyle {
    var glow: Color = Sky.ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? 0.94 : 1)
            .shadow(color: glow.opacity(pressed ? 0.7 : 0), radius: pressed ? 18 : 0)
            .animation(.spring(duration: 0.25), value: pressed)
            .sensoryFeedback(.impact(weight: .light), trigger: pressed) { !$0 && $1 }
    }
}
