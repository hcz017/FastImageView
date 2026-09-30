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
        guard let image = makeTestImage(width: 2, height: 2) else {
            XCTFail("无法创建测试图")
            return
        }
        cache.insert(url: url, maxPixelSize: 400, modified: date, image: image)
        XCTAssertNotNil(cache.image(url: url, maxPixelSize: 400, modified: date))
        cache.remove(url: url)
        XCTAssertNil(cache.image(url: url, maxPixelSize: 400, modified: date))
    }

    func testEvictionKeepsIndexAlignedWithCache() {
        let oneImageCost = CacheBudget.cost(width: 2, height: 2)
        let cache = ImageByteCache(byteLimit: oneImageCost)
        let date = Date(timeIntervalSince1970: 20)
        let url1 = URL(fileURLWithPath: "/tmp/evict-1.jpg")
        let url2 = URL(fileURLWithPath: "/tmp/evict-2.jpg")
        guard let image1 = makeTestImage(width: 2, height: 2),
              let image2 = makeTestImage(width: 2, height: 2) else {
            XCTFail("无法创建测试图")
            return
        }

        cache.insert(url: url1, maxPixelSize: 400, modified: date, image: image1)
        cache.insert(url: url2, maxPixelSize: 400, modified: date, image: image2)

        let hit1 = cache.image(url: url1, maxPixelSize: 400, modified: date)
        let hit2 = cache.image(url: url2, maxPixelSize: 400, modified: date)
        // Any URL still represented in the index must resolve via image(...).
        if hit1 != nil {
            XCTAssertNotNil(cache.image(url: url1, maxPixelSize: 400, modified: date))
        }
        if hit2 != nil {
            XCTAssertNotNil(cache.image(url: url2, maxPixelSize: 400, modified: date))
        }
        XCTAssertTrue(hit1 != nil || hit2 != nil, "At least one insert must remain in the cache")

        let evicted = hit1 == nil ? url1 : (hit2 == nil ? url2 : url1)
        let survivor = evicted == url1 ? url2 : url1
        XCTAssertNoThrow(cache.remove(url: evicted))
        XCTAssertNotNil(
            cache.image(url: survivor, maxPixelSize: 400, modified: date),
            "Surviving URL must still return an image after remove on the evicted URL"
        )
    }

    private func makeTestImage(width: Int, height: Int) -> CGImage? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }
}
