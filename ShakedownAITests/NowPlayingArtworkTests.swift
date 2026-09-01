import Testing
import UIKit
@testable import ShakedownAI

struct NowPlayingArtworkTests {
    @Test func stubRendersWithMarkAndText() throws {
        let image = NowPlayingCoordinator.renderStubImage(dateText: "May 8, 1977",
                                                          venueText: "Barton Hall, Cornell University")
        #expect(image.size == CGSize(width: 600, height: 600))
        #expect(image.pngData() != nil)
    }

    @Test func wideLayoutsRenderThreeByTwo() throws {
        for layout in [NowPlayingCoordinator.StubLayout.wide, .banner] {
            let image = NowPlayingCoordinator.renderStubImage(dateText: "May 8, 1977",
                                                              venueText: "Barton Hall, Cornell University",
                                                              layout: layout)
            #expect(image.size == CGSize(width: 900, height: 600))
            #expect(image.pngData() != nil)
        }
    }

    @Test func stubCacheKeysByLayout() {
        let show = Show.artworkPlaceholder(date: "1977-05-08", venue: "Barton Hall")
        let square = StubArtwork.image(for: show)
        let wide = StubArtwork.image(for: show, layout: .wide)
        #expect(square.size != wide.size)
        #expect(StubArtwork.image(for: show, layout: .wide) === wide)
    }
}
