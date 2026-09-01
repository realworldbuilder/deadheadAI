import Foundation
import Observation

/// The live facts the Explore sky carries: tonight's moon, how many nights
/// the band played this date, how full the listener's journal is, and which
/// show the emblem opens. Everything comes from the bundle, the catalog, or
/// local stores — nothing here ever touches the network.
@Observable
final class ExploreSkyModel {
    var onThisDayCount: Int?
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
        } else {
            onThisDayCount = nil
        }
    }

    var onThisDayCaption: String? {
        onThisDayCount.map { Self.onThisDayCaption(date: .now, count: $0) }
    }

    var journalCaption: String? { Self.journalCaption(count: journalCount) }

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
}
