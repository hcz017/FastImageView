import CoreGraphics
import XCTest
@testable import FastImageViewCore

final class ThumbnailDiskStoreTests: XCTestCase {
    func testKeyChangesWhenTheFileOrItsSizeChanges() {
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let key = ThumbnailDiskKey.make(path: "/pics/a.jpg", maxPixelSize: 400, modified: modified)
        XCTAssertEqual(key.count, 64)
        XCTAssertEqual(
            ThumbnailDiskKey.make(path: "/pics/a.jpg", maxPixelSize: 400, modified: modified),
            key
        )
        XCTAssertNotEqual(
            ThumbnailDiskKey.make(path: "/pics/b.jpg", maxPixelSize: 400, modified: modified),
            key
        )
        XCTAssertNotEqual(
            ThumbnailDiskKey.make(path: "/pics/a.jpg", maxPixelSize: 800, modified: modified),
            key
        )
        XCTAssertNotEqual(
            ThumbnailDiskKey.make(path: "/pics/a.jpg", maxPixelSize: 400, modified: modified.addingTimeInterval(1)),
            key
        )
    }

    func testLiveDirectoryIsTheAppThumbnailCache() {
        let path = ThumbnailDiskStore.liveDirectory().path
        XCTAssertTrue(path.hasSuffix("/Caches/local.FastImageView/Thumbnails"))
    }

    func testIndexDropsTheLeastRecentlyUsedFile() {
        var index = ThumbnailDiskIndex(byteLimit: 100)
        XCTAssertEqual(
            index.remember(key: "a", fileName: "a.jpg", bytes: 60, sourcePath: "/a", at: date(1)),
            []
        )
        XCTAssertEqual(
            index.remember(key: "b", fileName: "b.jpg", bytes: 60, sourcePath: "/b", at: date(2)),
            ["a.jpg"]
        )
        XCTAssertEqual(index.totalBytes, 60)
    }

    func testTouchProtectsAFileFromEviction() {
        var index = ThumbnailDiskIndex(byteLimit: 100)
        _ = index.remember(key: "a", fileName: "a.jpg", bytes: 40, sourcePath: "/a", at: date(1))
        _ = index.remember(key: "b", fileName: "b.jpg", bytes: 40, sourcePath: "/b", at: date(2))
        index.touch(key: "a", at: date(3))
        XCTAssertEqual(
            index.remember(key: "c", fileName: "c.jpg", bytes: 40, sourcePath: "/c", at: date(4)),
            ["b.jpg"]
        )
        XCTAssertNotNil(index.records["a"])
        XCTAssertNotNil(index.records["c"])
    }

    func testASingleOversizedThumbnailIsKept() {
        var index = ThumbnailDiskIndex(byteLimit: 50)
        XCTAssertEqual(
            index.remember(key: "big", fileName: "big.jpg", bytes: 80, sourcePath: "/big", at: date(1)),
            []
        )
        XCTAssertEqual(index.totalBytes, 80)
    }

    func testRemoveSourceDropsEverySizeForThatPath() {
        var index = ThumbnailDiskIndex(byteLimit: 1_000)
        _ = index.remember(key: "a400", fileName: "a400.jpg", bytes: 10, sourcePath: "/a", at: date(1))
        _ = index.remember(key: "a800", fileName: "a800.jpg", bytes: 20, sourcePath: "/a", at: date(2))
        _ = index.remember(key: "b", fileName: "b.jpg", bytes: 10, sourcePath: "/b", at: date(3))
        XCTAssertEqual(Set(index.removeSource("/a")), ["a400.jpg", "a800.jpg"])
        XCTAssertNil(index.records["a400"])
        XCTAssertNotNil(index.records["b"])
    }

    func testRoundTripKeepsTheThumbnailAfterANewStoreOpensTheFolder() throws {
        let directory = try makeDirectory()
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let store = try ThumbnailDiskStore(directory: directory)
        store.store(path: "/pics/a.jpg", maxPixelSize: 400, modified: modified, image: solidImage(width: 12, height: 8))

        let reopened = try ThumbnailDiskStore(directory: directory)
        let image = try XCTUnwrap(reopened.image(path: "/pics/a.jpg", maxPixelSize: 400, modified: modified))
        XCTAssertEqual(image.width, 12)
        XCTAssertEqual(image.height, 8)
        XCTAssertNil(reopened.image(path: "/pics/a.jpg", maxPixelSize: 400, modified: modified.addingTimeInterval(5)))
    }

    func testStoreEvictsTheOldestFileOnceTheCapIsPassed() throws {
        let directory = try makeDirectory()
        let store = try ThumbnailDiskStore(directory: directory, byteLimit: 1)
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        store.store(path: "/pics/old.jpg", maxPixelSize: 400, modified: modified, image: solidImage(width: 16, height: 16))
        store.store(path: "/pics/new.jpg", maxPixelSize: 400, modified: modified, image: solidImage(width: 16, height: 16))

        XCTAssertNil(store.image(path: "/pics/old.jpg", maxPixelSize: 400, modified: modified))
        XCTAssertNotNil(store.image(path: "/pics/new.jpg", maxPixelSize: 400, modified: modified))
    }

    func testReadingAThumbnailMakesItNewerThanOneThatWasOnlyStored() throws {
        let directory = try makeDirectory()
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try ThumbnailDiskStore(directory: directory, byteLimit: 50_000_000)
        first.store(path: "/pics/a.jpg", maxPixelSize: 400, modified: modified, image: solidImage(width: 32, height: 32))
        first.store(path: "/pics/b.jpg", maxPixelSize: 400, modified: modified, image: solidImage(width: 32, height: 32))
        XCTAssertNotNil(first.image(path: "/pics/a.jpg", maxPixelSize: 400, modified: modified))
        first.flush()

        let probe = try makeDirectory()
        let probeStore = try ThumbnailDiskStore(directory: probe, byteLimit: 50_000_000)
        probeStore.store(path: "/pics/c.jpg", maxPixelSize: 400, modified: modified, image: solidImage(width: 8, height: 8))
        let aBytes = try fileBytes(directory: directory, path: "/pics/a.jpg", maxPixelSize: 400, modified: modified)
        let cBytes = try fileBytes(directory: probe, path: "/pics/c.jpg", maxPixelSize: 400, modified: modified)
        let second = try ThumbnailDiskStore(directory: directory, byteLimit: aBytes + cBytes)
        second.store(path: "/pics/c.jpg", maxPixelSize: 400, modified: modified, image: solidImage(width: 8, height: 8))

        XCTAssertNotNil(second.image(path: "/pics/a.jpg", maxPixelSize: 400, modified: modified))
        XCTAssertNil(second.image(path: "/pics/b.jpg", maxPixelSize: 400, modified: modified))
        XCTAssertNotNil(second.image(path: "/pics/c.jpg", maxPixelSize: 400, modified: modified))
    }

    func testRemoveDeletesTheCachedFile() throws {
        let directory = try makeDirectory()
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let store = try ThumbnailDiskStore(directory: directory)
        store.store(path: "/pics/a.jpg", maxPixelSize: 400, modified: modified, image: solidImage(width: 8, height: 8))
        store.remove(path: "/pics/a.jpg")
        XCTAssertNil(store.image(path: "/pics/a.jpg", maxPixelSize: 400, modified: modified))
    }

    func testPipelineReadsTheDiskThumbnailAfterTheOriginalDisappears() async throws {
        let directory = try makeDirectory()
        let store = try ThumbnailDiskStore(directory: directory)
        let picture = try copiedFixture()
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let file = ImageFile(
            url: picture,
            filename: picture.lastPathComponent,
            format: .jpeg,
            modificationDate: modified,
            iCloudState: .notCloud
        )
        let pipeline = await LivePreviewPipeline(diskThumbnails: store)
        await pipeline.requestThumbnail(file: file)
        try await waitUntil { await pipeline.cachedThumbnail(file: file) != nil }
        XCTAssertNotNil(store.image(path: picture.path, maxPixelSize: PreviewMaxPixel.thumbnail, modified: modified))

        await pipeline.showViewer(current: file, previous: nil, next: nil, maxPixelSize: 1200)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNil(store.image(path: picture.path, maxPixelSize: 1200, modified: modified))

        await pipeline.reset()
        XCTAssertNotNil(store.image(path: picture.path, maxPixelSize: PreviewMaxPixel.thumbnail, modified: modified))

        try FileManager.default.removeItem(at: picture)
        let again = await LivePreviewPipeline(diskThumbnails: store)
        await again.requestThumbnail(file: file)
        try await waitUntil { await again.cachedThumbnail(file: file) != nil }
        let cached = await again.cachedThumbnail(file: file)
        XCTAssertNotNil(cached)
        let failed = await again.didFail(url: picture)
        XCTAssertFalse(failed)
    }

    func testCancellingAFileDropsItsDiskThumbnail() async throws {
        let directory = try makeDirectory()
        let store = try ThumbnailDiskStore(directory: directory)
        let picture = try copiedFixture()
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let file = ImageFile(
            url: picture,
            filename: picture.lastPathComponent,
            format: .jpeg,
            modificationDate: modified,
            iCloudState: .notCloud
        )
        let pipeline = await LivePreviewPipeline(diskThumbnails: store)
        await pipeline.requestThumbnail(file: file)
        try await waitUntil { await pipeline.cachedThumbnail(file: file) != nil }
        await pipeline.cancel(url: picture)
        XCTAssertNil(store.image(path: picture.path, maxPixelSize: PreviewMaxPixel.thumbnail, modified: modified))
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func makeDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("FastImageView-thumbs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func copiedFixture() throws -> URL {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/sample.jpg")
        let copy = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("FastImageView-src-\(UUID().uuidString).jpg")
        try FileManager.default.copyItem(at: fixture, to: copy)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: copy)
        }
        return copy
    }

    private func fileBytes(directory: URL, path: String, maxPixelSize: Int, modified: Date) throws -> Int {
        let name = ThumbnailDiskKey.make(path: path, maxPixelSize: maxPixelSize, modified: modified) + ".jpg"
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    private func solidImage(width: Int, height: Int) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func waitUntil(timeout: TimeInterval = 3, _ predicate: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !predicate() {
            if Date() >= deadline {
                XCTFail("等待缩略图超时")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
