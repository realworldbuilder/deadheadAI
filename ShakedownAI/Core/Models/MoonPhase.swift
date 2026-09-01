import Foundation

/// Where the moon is in its month, as a fraction of a lunation: 0 is new,
/// 0.5 is full, and it wraps back toward 0. Plain arithmetic from a reference
/// new moon — no ephemeris — so it lands within a few hours of the truth,
/// which is all a forty-point moon on the Explore sky needs.
nonisolated enum MoonPhase {
    /// Mean length of a lunation, in days.
    static let synodicMonth: Double = 29.530588853

    /// A well-documented new moon: 2000-01-06 18:14 UTC.
    static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)

    static func fraction(on date: Date) -> Double {
        let days = date.timeIntervalSince(referenceNewMoon) / 86_400
        let cycles = days / synodicMonth
        let fraction = cycles - floor(cycles)
        // `floor` already handles dates before the reference; clamp the
        // floating-point edge so the result is always in 0..<1.
        return fraction >= 1 ? 0 : max(fraction, 0)
    }
}
