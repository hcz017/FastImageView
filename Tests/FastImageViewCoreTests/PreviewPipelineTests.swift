import XCTest
@testable import FastImageViewCore

final class PreviewPipelineTests: XCTestCase {
    func testJPEGAndPNGProduceThumbnailsWithinCap() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        let decoder = ImageIOThumbnailDecoder()
        for name in ["sample.jpg", "sample.png"] {
            let url = root.appendingPathComponent(name)
            let image = try XCTUnwrap(decoder.thumbnail(url: url, maxPixelSize: 400))
            XCTAssertLessThanOrEqual(max(image.width, image.height), 400)
        }
    }

    func testNEFFixtureIsOptional() throws {
        guard let path = ProcessInfo.processInfo.environment["FASTIMAGEVIEW_NEF_FIXTURE"] else {
            throw XCTSkip("FASTIMAGEVIEW_NEF_FIXTURE 未设置")
        }
        let image = try XCTUnwrap(ImageIOThumbnailDecoder().thumbnail(url: URL(fileURLWithPath: path), maxPixelSize: 16384))
        XCTAssertLessThanOrEqual(max(image.width, image.height), 16384)
    }
}
