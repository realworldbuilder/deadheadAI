import Foundation
import Observation

/// The live facts the Explore sky carries: tonight's moon, how many nights
/// the band played this date, the span of years the catalog covers, how full
/// the listener's journal is, and which show the emblem opens. Everything comes from the bundle, the catalog, or
/// local stores — nothing here ever touches the network.
@Observable
final class ExploreSkyModel {
    var onThisDayCount: Int?
    var yearRange: ClosedRange<Int>?
    var journalCount = 0
    var moonPhase = MoonPhase.fraction(on: .now)
    var hero: NotableShow?

    func refresh(env: AppEnvironment) async {
        let now = Date.now
        moonPhase = MoonPhase.fraction(on: now)
        journalCount = env.library.journalEntries.count
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 1
        hero = env.knowledgeBase.heroShow(dayOfYear: dayOfYear, taste: env.history.tasteSnapshot)
        if env.catalog.isAvailable {
            onThisDayCount = await env.catalog.shows(onMonthDay: HomeModel.monthDayString(now)).count
            yearRange = Self.yearRange(await env.catalog.yearCounts())
        } else {
            onThisDayCount = nil
            yearRange = nil
        }
    }

    /// "Tuesday, September 1 · Waxing gibbous"
    var dateline: String { Self.dateline(date: .now, moonPhase: moonPhase) }

    var onThisDayCaption: String? {
        onThisDayCount.map { Self.onThisDayCaption(date: .now, count: $0) }
    }

    var journalCaption: String? { Self.journalCaption(count: journalCount) }

    /// "1965–95". Quiet when the catalog isn't bundled.
    var yearsCaption: String? { yearRange.map(Self.yearsCaption) }

    nonisolated static func dateline(date: Date, moonPhase: Double) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return "\(day) · \(MoonPhase.name(for: moonPhase))"
    }

    /// "Sep 1 · 12 shows". A date the band never played just shows the date.
    nonisolated static func onThisDayCaption(date: Date, count: Int) -> String {
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        guard count > 0 else { return day }
        return "\(day) · \(count) \(count == 1 ? "show" : "shows")"
    }

    /// "3 entries". An empty journal doesn't advertise.
    nonisolated static func journalCaption(count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? "entry" : "entries")"
    }

    /// The first and last year the catalog knows, or nil when it knows none.
    nonisolated static func yearRange(_ counts: [(year: Int, count: Int)]) -> ClosedRange<Int>? {
        let years = counts.map(\.year)
        guard let first = years.min(), let last = years.max() else { return nil }
        return first...last
    }

    /// "1965–95": a span inside one century drops the repeated digits; a
    /// single year is just the year.
    nonisolated static func yearsCaption(_ range: ClosedRange<Int>) -> String {
        let lower = range.lowerBound, upper = range.upperBound
        if lower == upper { return String(lower) }
        if lower / 100 == upper / 100 {
            return "\(lower)–" + String(format: "%02d", upper % 100)
        }
        return "\(lower)–\(upper)"
    }
}
