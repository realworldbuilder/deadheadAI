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
}
