import Foundation
import Testing
@testable import ShakedownAI

struct ExploreSkyTests {
    @Test func moonIsNewAtTheReference() {
        #expect(MoonPhase.fraction(on: MoonPhase.referenceNewMoon) == 0)
    }

    @Test func moonIsFullOnAKnownFullMoon() {
        // 2024-01-25 17:54 UTC — the Wolf Moon.
        let full = Date(timeIntervalSince1970: 1_706_205_240)
        #expect(abs(MoonPhase.fraction(on: full) - 0.5) < 0.02)
    }

    @Test func moonFractionStaysInRange() {
        for days in stride(from: -4000, through: 4000, by: 37) {
            let date = MoonPhase.referenceNewMoon.addingTimeInterval(Double(days) * 86_400)
            let f = MoonPhase.fraction(on: date)
            #expect(f >= 0 && f < 1)
        }
    }

    @Test func moonNamesFollowTheEighths() {
        #expect(MoonPhase.name(for: 0) == "New moon")
        #expect(MoonPhase.name(for: 0.25) == "First quarter")
        #expect(MoonPhase.name(for: 0.5) == "Full moon")
        #expect(MoonPhase.name(for: 0.75) == "Last quarter")
        #expect(MoonPhase.name(for: 0.4) == "Waxing gibbous")
        // The tail of the cycle rounds back around to new.
        #expect(MoonPhase.name(for: 0.99) == "New moon")
    }

    @Test func datelineNamesTheDayAndTheMoon() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
        #expect(ExploreSkyModel.dateline(date: date, moonPhase: 0.5) == "Tuesday, September 1 · Full moon")
    }

    @Test func onThisDayCaptionReadsLikeADateline() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
        #expect(ExploreSkyModel.onThisDayCaption(date: date, count: 12) == "Sep 1 · 12 shows")
        #expect(ExploreSkyModel.onThisDayCaption(date: date, count: 1) == "Sep 1 · 1 show")
        #expect(ExploreSkyModel.onThisDayCaption(date: date, count: 0) == "Sep 1")
    }

    @Test func journalCaptionStaysQuietWhenEmpty() {
        #expect(ExploreSkyModel.journalCaption(count: 0) == nil)
        #expect(ExploreSkyModel.journalCaption(count: 1) == "1 entry")
        #expect(ExploreSkyModel.journalCaption(count: 3) == "3 entries")
    }

    @Test func yearsCaptionCollapsesTheCentury() {
        #expect(ExploreSkyModel.yearsCaption(1965...1995) == "1965–95")
        #expect(ExploreSkyModel.yearsCaption(1977...1977) == "1977")
        #expect(ExploreSkyModel.yearsCaption(1995...2003) == "1995–2003")
    }

    @Test func yearRangeSpansTheCatalog() {
        #expect(ExploreSkyModel.yearRange([]) == nil)
        #expect(ExploreSkyModel.yearRange([(year: 1972, count: 1), (year: 1966, count: 2)]) == 1966...1972)
    }
}
