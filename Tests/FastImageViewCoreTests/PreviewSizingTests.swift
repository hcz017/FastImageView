import ImageIO
import XCTest
@testable import FastImageViewCore

final class PreviewSizingTests: XCTestCase {
    func testThumbnailAndFitSizes() {
        XCTAssertEqual(PreviewMaxPixel.thumbnail, 400)
        XCTAssertEqual(PreviewMaxPixel.viewer(fit: .fit, screenLongEdge: 1800, isRaw: true), 1800)
        XCTAssertEqual(PreviewMaxPixel.viewer(fit: .actual, screenLongEdge: 1800, isRaw: true), 16384)
        XCTAssertEqual(ImageIOThumbnailOptions.imageIndex, 0)
    }

    func testOptionsAskOnlyForAThumbnail() {
        let raw = ImageIOThumbnailOptions.dictionary(maxPixelSize: 400)
        XCTAssertEqual(raw[kCGImageSourceCreateThumbnailFromImageAlways] as? Bool, true)
        XCTAssertEqual(raw[kCGImageSourceCreateThumbnailWithTransform] as? Bool, true)
        XCTAssertEqual(raw[kCGImageSourceThumbnailMaxPixelSize] as? Int, 400)
        XCTAssertEqual(raw[kCGImageSourceShouldCacheImmediately] as? Bool, true)
        XCTAssertNil(raw[kCGImageSourceShouldAllowFloat] )
    }
}
