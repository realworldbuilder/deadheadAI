import Foundation
import SwiftUI
import Testing
@testable import ShakedownAI

private func scan(_ kind: CatalogImage.Kind, _ name: String, width: Int? = nil, height: Int? = nil,
                  position: Int = 0) -> CatalogImage {
    CatalogImage(date: "1977-05-08", position: position, kind: kind,
                 url: "https://cdn.jerrygarcia.com/u/\(name)", width: width, height: height)
}

struct ScanGalleryTests {
    @Test func emptyGalleryHasNoHeroOrStrip() {
        let gallery = ScanGallery()
        #expect(gallery.lead == nil)
        #expect(!gallery.hasScans)
        #expect(!gallery.showsStrip)
        #expect(gallery.viewerPages(dateText: "May 8, 1977").isEmpty)
    }

    @Test func singleScanIsTheHeroWithoutAStrip() {
        let gallery = ScanGallery(images: [scan(.ticket, "t.jpg")])
        #expect(gallery.lead?.kind == .ticket)
        #expect(gallery.others.isEmpty)
        #expect(gallery.hasScans)
        #expect(!gallery.showsStrip)
    }

    @Test func leadIsTheCoverAndTheRestRideTheStrip() {
        let images = [scan(.ticket, "t.jpg"), scan(.poster, "p.jpg", position: 1),
                      scan(.backstagePass, "b.jpg", position: 2)]
        let gallery = ScanGallery(images: images)
        #expect(gallery.lead == images[0])
        #expect(gallery.others == Array(images[1...]))
        #expect(gallery.showsStrip)
    }

    @Test func viewerPagesFollowGalleryOrderAndCaptionByKind() {
        let images = [scan(.ticket, "t.jpg"), scan(.backstagePass, "b.jpg", position: 1)]
        let gallery = ScanGallery(images: images)
        let pages = gallery.viewerPages(dateText: "May 8, 1977")
        #expect(pages.map(\.caption) == ["Ticket", "Backstage pass"])
        #expect(pages.first?.accessibilityLabel == "Ticket scan for May 8, 1977")
        #expect(gallery.pageIndex(of: images[1], dateText: "May 8, 1977") == 1)
    }
}

struct ScanHeroTests {
    @Test func unknownDimensionsFallBackToSixteenByNine() {
        #expect(ScanHero.bannerAspect(width: nil, height: nil) == 16.0 / 9.0)
        #expect(ScanHero.bannerAspect(width: 100, height: 0) == 16.0 / 9.0)
        #expect(ScanHero.bannerAspect(ratio: nil) == 16.0 / 9.0)
    }

    @Test func aspectIsClampedBetweenPosterAndTicket() {
        #expect(ScanHero.bannerAspect(width: 2400, height: 1000) == 2.4)
        #expect(ScanHero.bannerAspect(width: 600, height: 900) == 1.25)
        #expect(abs(ScanHero.bannerAspect(width: 1600, height: 900) - 16.0 / 9.0) < 0.001)
    }

    @Test func postersAndPortraitsCropFromTheTop() {
        #expect(ScanHero.cropAlignment(kind: .poster, width: nil, height: nil) == .top)
        #expect(ScanHero.cropAlignment(kind: .other, width: 600, height: 900) == .top)
        #expect(ScanHero.cropAlignment(kind: .ticket, width: 457, height: 157) == .center)
        #expect(ScanHero.cropAlignment(kind: .backstagePass, width: nil, height: nil) == .center)
    }

    @Test func thumbnailsAreSquareWhenUnknownAndAtMostTwoToOne() {
        #expect(ScanThumbnail.thumbnailAspect(ratio: nil) == 1)
        #expect(ScanThumbnail.thumbnailAspect(ratio: 0.6) == 1)
        #expect(ScanThumbnail.thumbnailAspect(ratio: 1.5) == 1.5)
        #expect(ScanThumbnail.thumbnailAspect(ratio: 3.0) == 2)
    }

    @Test func kindLabels() {
        #expect(CatalogImage.Kind.ticket.label == "Ticket")
        #expect(CatalogImage.Kind.backstagePass.label == "Backstage pass")
        #expect(CatalogImage.Kind.backstagePass.shortLabel == "Pass")
        #expect(CatalogImage.Kind.poster.shortLabel == "Poster")
        #expect(CatalogImage.Kind.other.label == "Scan")
        #expect(CatalogImage.Kind(rawValue: "backstage_pass") == .backstagePass)
    }
}

struct ImageViewerTests {
    @Test func captionCountsOnlyWithSiblings() {
        #expect(ImageViewer.caption(index: 1, count: 3, label: "Ticket") == "Ticket · 2 of 3")
        #expect(ImageViewer.caption(index: 0, count: 1, label: "Poster") == "Poster")
    }

    @Test func dismissNeedsDistanceOrAFlick() {
        #expect(!ImageViewer.shouldDismiss(translation: 60, predictedEnd: 100))
        #expect(ImageViewer.shouldDismiss(translation: 140, predictedEnd: 150))
        #expect(ImageViewer.shouldDismiss(translation: 40, predictedEnd: 400))
        #expect(!ImageViewer.shouldDismiss(translation: -140, predictedEnd: -400))
    }

    @Test func onlyClearlyDownwardDragsCountAsVertical() {
        #expect(ImageViewer.isVerticalDrag(dx: 10, dy: 60))
        #expect(!ImageViewer.isVerticalDrag(dx: 60, dy: 60))
        #expect(!ImageViewer.isVerticalDrag(dx: 0, dy: -60))
    }
}

struct ShowDetailScansTests {
    @Test func modelLoadsTheNightsScansFromTheCatalog() async {
        let catalog = MockShowCatalog()
        catalog.imagesByDate["1977-05-08"] = [
            scan(.ticket, "t.jpg", width: 457, height: 157),
            scan(.backstagePass, "b.jpg", width: 219, height: 216, position: 1),
        ]
        let model = ShowDetailModel(show: MockData.cornell, metadata: MockRecordingProvider(),
                                    recordings: MockRecordingProvider(), ai: MockAIProvider(),
                                    catalog: catalog)
        await model.loadCatalogContext()
        #expect(model.images.count == 2)
        #expect(model.gallery.lead?.url == "https://cdn.jerrygarcia.com/u/t.jpg")
        #expect(model.gallery.showsStrip)
    }

    @Test func unavailableCatalogLeavesNoScans() async {
        let catalog = MockShowCatalog()
        catalog.isAvailable = false
        catalog.imagesByDate["1977-05-08"] = [scan(.ticket, "t.jpg")]
        let model = ShowDetailModel(show: MockData.cornell, metadata: MockRecordingProvider(),
                                    recordings: MockRecordingProvider(), ai: MockAIProvider(),
                                    catalog: catalog)
        await model.loadCatalogContext()
        #expect(model.images.isEmpty)
        #expect(!model.gallery.hasScans)
    }
}
