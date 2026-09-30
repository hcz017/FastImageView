import XCTest
@testable import FastImageViewCore

final class PreviewSchedulerTests: XCTestCase {
    func testViewerJumpsAheadOfQueuedThumbnails() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        for index in 0..<6 {
            _ = scheduler.enqueue(url: folder.appendingPathComponent("\(index).jpg"), maxPixelSize: 400, priority: .thumbnail)
        }
        var running = 0
        while scheduler.startNext(runningCount: running) != nil { running += 1 }
        XCTAssertEqual(running, 4)
        scheduler.yieldQueuedThumbnails()
        let currentURL = folder.appendingPathComponent("current.jpg")
        _ = scheduler.enqueue(url: currentURL, maxPixelSize: 1800, priority: .current)
        _ = scheduler.enqueue(url: folder.appendingPathComponent("side.jpg"), maxPixelSize: 400, priority: .thumbnail)
        running = 3
        let next = scheduler.startNext(runningCount: running)
        XCTAssertEqual(next?.url, currentURL)
        XCTAssertEqual(next?.priority, .current)
    }

    func testPrefetchBeatsThumbnail() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        _ = scheduler.enqueue(url: folder.appendingPathComponent("t.jpg"), maxPixelSize: 400, priority: .thumbnail)
        let prefetch = folder.appendingPathComponent("p.jpg")
        _ = scheduler.enqueue(url: prefetch, maxPixelSize: 1800, priority: .prefetch)
        XCTAssertEqual(scheduler.startNext(runningCount: 0)?.url, prefetch)
    }
}
