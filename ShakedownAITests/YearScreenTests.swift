import Foundation
import Testing
@testable import ShakedownAI

struct YearScreenTests {
    /// A catalog night with just enough to group by; `best` nil means the
    /// night has no playable tape.
    private func night(_ date: String, id: String? = nil, best: String? = "keep") -> CatalogShow {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        return CatalogShow(
            showID: id ?? date, date: date, year: parts[0], month: parts[1], day: parts[2],
            eraID: nil, venue: "Somewhere", city: nil, state: nil,
            setlistStatus: .none, recordingCount: best == nil ? 0 : 1,
            bestIdentifier: best.map { _ in "gd\(date).\(id ?? "sbd")" }, bestSourceType: .soundboard,
            avgRating: nil, totalReviews: 0, totalDownloads: 0)
    }

    @Test func bucketsAreMonthOrderedAndDateOrderedWithin() {
        let buckets = YearScreen.monthBuckets([
            night("1977-10-29"), night("1977-05-22"), night("1977-03-18"), night("1977-05-08"),
        ])
        #expect(buckets.map(\.month) == [3, 5, 10])
        #expect(buckets[1].shows.map(\.dateString) == ["1977-05-08", "1977-05-22"])
    }

    @Test func earlyAndLateShowsKeepTheirOrder() {
        let buckets = YearScreen.monthBuckets([
            night("1970-02-13", id: "1970-02-13-late"),
            night("1970-02-13", id: "1970-02-13-early"),
        ])
        #expect(buckets.count == 1)
        #expect(buckets[0].shows.map(\.identifier) == ["gd1970-02-13.1970-02-13-early", "gd1970-02-13.1970-02-13-late"])
    }

    @Test func monthsWithNoPlayableTapeAreDropped() {
        let buckets = YearScreen.monthBuckets([
            night("1966-01-08", best: nil),   // whole month unplayable → gone
            night("1966-03-12"),
            night("1966-03-25", best: nil),   // one row gone, month stays
        ])
        #expect(buckets.map(\.month) == [3])
        #expect(buckets[0].shows.map(\.dateString) == ["1966-03-12"])
    }

    @Test func emptyInputYieldsNoBuckets() {
        #expect(YearScreen.monthBuckets([]).isEmpty)
    }

    @Test func namesAreEnglishMonthSymbols() {
        let may = YearScreen.MonthBucket(month: 5, shows: [])
        let september = YearScreen.MonthBucket(month: 9, shows: [])
        #expect(may.name == "May" && may.shortName == "May")
        #expect(september.name == "September" && september.shortName == "Sep")
    }
}
