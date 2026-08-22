import Foundation
import Testing
@testable import ShakedownAI

struct ShareTests {
    private var cornell: Show {
        Show(identifier: "gd1977-05-08.sbd.hicks.4982.sbeok.shnf",
             title: "Grateful Dead Live at Barton Hall",
             date: DateComponents(calendar: .init(identifier: .gregorian),
                                  timeZone: TimeZone(identifier: "UTC"),
                                  year: 1977, month: 5, day: 8).date,
             dateString: "1977-05-08",
             venue: "Barton Hall, Cornell University",
             location: "Ithaca, NY")
    }

    @Test func showShareURLPointsAtArchiveDetails() {
        #expect(cornell.shareURL.absoluteString ==
                "https://archive.org/details/gd1977-05-08.sbd.hicks.4982.sbeok.shnf")
    }

    @Test func trackShareURLDeepLinksTheFile() {
        let track = Track(fileName: "gd77-05-08d1t01.mp3", title: "Minglewood Blues")
        #expect(cornell.shareURL(for: track).absoluteString ==
                "https://archive.org/details/gd1977-05-08.sbd.hicks.4982.sbeok.shnf/gd77-05-08d1t01.mp3")
    }

    @Test func trackShareURLEncodesAwkwardFileNames() {
        let track = Track(fileName: "disc 1/scarlet 100%.mp3", title: "Scarlet Begonias")
        let url = cornell.shareURL(for: track)
        #expect(url.absoluteString.contains("scarlet%20100%25.mp3"))
        #expect(url.host() == "archive.org")
    }

    @Test func shareTextNamesTheBandShowAndTrack() {
        #expect(cornell.shareText() ==
                "Grateful Dead — May 8, 1977 · Barton Hall, Cornell University · Ithaca, NY")
        let track = Track(fileName: "t01.mp3", title: "Morning Dew")
        #expect(cornell.shareText(track: track).hasPrefix("Morning Dew — Grateful Dead — May 8, 1977"))
    }
}
