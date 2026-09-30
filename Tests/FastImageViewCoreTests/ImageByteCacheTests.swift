import CoreGraphics
import XCTest
@testable import FastImageViewCore

final class ImageByteCacheTests: XCTestCase {
    func testBudgetsAndRoundTrip() {
        XCTAssertEqual(CacheBudget.thumbnailBytes, 128 * 1024 * 1024)
        XCTAssertEqual(CacheBudget.viewerBytes, 512 * 1024 * 1024)
        XCTAssertEqual(CacheBudget.cost(width: 6000, height: 4000), 6000 * 4000 * 4)
        let cache = ImageByteCache(byteLimit: CacheBudget.thumbnailBytes)
        XCTAssertEqual(cache.byteLimit, CacheBudget.thumbnailBytes)
        let url = URL(fileURLWithPath: "/tmp/a.jpg")
        let date = Date(timeIntervalSince1970: 10)
        guard let image = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage() else {
            XCTFail("无法创建测试图")
            return
        }
        cache.insert(url: url, maxPixelSize: 400, modified: date, image: image)
        XCTAssertNotNil(cache.image(url: url, maxPixelSize: 400, modified: date))
        cache.remove(url: url)
        XCTAssertNil(cache.image(url: url, maxPixelSize: 400, modified: date))
    }
}
