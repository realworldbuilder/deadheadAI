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
}
