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
        let url = URL(fileURLWithPath: path)
        let decoder = ImageIOThumbnailDecoder()
        let fit = try XCTUnwrap(decoder.thumbnail(url: url, maxPixelSize: 900, isRaw: true))
        let zoomed = try XCTUnwrap(decoder.thumbnail(url: url, maxPixelSize: 16384, isRaw: true))
        XCTAssertLessThanOrEqual(max(zoomed.width, zoomed.height), 16384)
        // RAW 必须始终走内嵌预览，否则 ImageIO 会按请求尺寸切换渲染路径，缩放时颜色跳变。
        XCTAssertEqual(fit.colorSpace?.name as String?, zoomed.colorSpace?.name as String?)
        XCTAssertEqual(fit.bitsPerComponent, zoomed.bitsPerComponent)
    }

    func testStaleEpochDropsThumbnail() {
        let url = URL(fileURLWithPath: "/tmp/thumb.jpg")
        let decision = PreviewDecodeWriteDecision.decide(
            jobEpoch: 1,
            currentEpoch: 2,
            priority: .thumbnail,
            url: url,
            wantedViewerURLs: []
        )
        XCTAssertFalse(decision.shouldWrite)
    }

    func testStaleEpochDropsViewerImage() {
        let url = URL(fileURLWithPath: "/tmp/viewer.jpg")
        let decision = PreviewDecodeWriteDecision.decide(
            jobEpoch: 0,
            currentEpoch: 1,
            priority: .current,
            url: url,
            wantedViewerURLs: [url]
        )
        XCTAssertFalse(decision.shouldWrite)
    }

    func testCurrentEpochAllowsThumbnail() {
        let url = URL(fileURLWithPath: "/tmp/thumb.jpg")
        let decision = PreviewDecodeWriteDecision.decide(
            jobEpoch: 3,
            currentEpoch: 3,
            priority: .thumbnail,
            url: url,
            wantedViewerURLs: []
        )
        XCTAssertTrue(decision.shouldWrite)
    }

    func testCurrentEpochDropsViewerURLNotInWantedSet() {
        let url = URL(fileURLWithPath: "/tmp/old.jpg")
        let wanted = Set([URL(fileURLWithPath: "/tmp/current.jpg")])
        let decision = PreviewDecodeWriteDecision.decide(
            jobEpoch: 5,
            currentEpoch: 5,
            priority: .prefetch,
            url: url,
            wantedViewerURLs: wanted
        )
        XCTAssertFalse(decision.shouldWrite)
    }

    func testCurrentEpochAllowsViewerURLThatIsWanted() {
        let url = URL(fileURLWithPath: "/tmp/current.jpg")
        let decision = PreviewDecodeWriteDecision.decide(
            jobEpoch: 5,
            currentEpoch: 5,
            priority: .current,
            url: url,
            wantedViewerURLs: [url]
        )
        XCTAssertTrue(decision.shouldWrite)
    }
}
