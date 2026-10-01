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

    func testDropQueuedViewerJobsKeepsWantedAndThumbnails() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        let current = folder.appendingPathComponent("current.jpg")
        let previous = folder.appendingPathComponent("prev.jpg")
        let next = folder.appendingPathComponent("next.jpg")
        let stale = folder.appendingPathComponent("stale.jpg")
        let thumb = folder.appendingPathComponent("thumb.jpg")

        _ = scheduler.enqueue(url: stale, maxPixelSize: 1800, priority: .current)
        _ = scheduler.enqueue(url: folder.appendingPathComponent("old-prefetch.jpg"), maxPixelSize: 1800, priority: .prefetch)
        _ = scheduler.enqueue(url: current, maxPixelSize: 1800, priority: .current)
        _ = scheduler.enqueue(url: previous, maxPixelSize: 1800, priority: .prefetch)
        _ = scheduler.enqueue(url: next, maxPixelSize: 1800, priority: .prefetch)
        _ = scheduler.enqueue(url: thumb, maxPixelSize: 400, priority: .thumbnail)

        let wanted: Set<URL> = [current, previous, next]
        let removed = scheduler.dropQueuedViewerJobs(keeping: wanted)

        XCTAssertEqual(Set(removed.map(\.url)), Set([
            stale,
            folder.appendingPathComponent("old-prefetch.jpg"),
        ]))
        XCTAssertTrue(removed.allSatisfy { $0.priority != .thumbnail })

        var remaining: [PreviewJob] = []
        while let job = scheduler.startNext(runningCount: remaining.count) {
            remaining.append(job)
        }
        XCTAssertEqual(Set(remaining.map(\.url)), Set([current, previous, next, thumb]))
        XCTAssertTrue(remaining.contains { $0.url == thumb && $0.priority == .thumbnail })
    }

    func testNewestThumbnailRunsBeforeOlderOnes() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        let older = folder.appendingPathComponent("older.jpg")
        let newer = folder.appendingPathComponent("newer.jpg")
        _ = scheduler.enqueueThumbnailFirst(url: older, maxPixelSize: 400)
        _ = scheduler.enqueueThumbnailFirst(url: newer, maxPixelSize: 400)
        XCTAssertEqual(scheduler.startNext(runningCount: 0)?.url, newer)
        XCTAssertEqual(scheduler.startNext(runningCount: 0)?.url, older)
    }

    func testRepeatedThumbnailRequestMovesItAhead() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        let first = folder.appendingPathComponent("first.jpg")
        let second = folder.appendingPathComponent("second.jpg")
        _ = scheduler.enqueueThumbnailFirst(url: first, maxPixelSize: 400)
        _ = scheduler.enqueueThumbnailFirst(url: second, maxPixelSize: 400)
        _ = scheduler.enqueueThumbnailFirst(url: first, maxPixelSize: 400)
        XCTAssertEqual(scheduler.startNext(runningCount: 0)?.url, first)
    }

    func testCancelQueuedThumbnailLeavesViewerJob() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        let photo = folder.appendingPathComponent("photo.jpg")
        _ = scheduler.enqueueThumbnailFirst(url: photo, maxPixelSize: 400)
        _ = scheduler.enqueue(url: photo, maxPixelSize: 1800, priority: .current)
        let removed = scheduler.cancelQueuedThumbnails(url: photo)
        XCTAssertEqual(removed.map(\.priority), [.thumbnail])
        XCTAssertEqual(scheduler.startNext(runningCount: 0)?.priority, .current)
    }

    func testYieldQueuedThumbnailsReturnsRemovedJobs() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        let a = folder.appendingPathComponent("a.jpg")
        let b = folder.appendingPathComponent("b.jpg")
        let viewer = folder.appendingPathComponent("v.jpg")
        _ = scheduler.enqueue(url: a, maxPixelSize: 400, priority: .thumbnail)
        _ = scheduler.enqueue(url: b, maxPixelSize: 400, priority: .thumbnail)
        _ = scheduler.enqueue(url: viewer, maxPixelSize: 1800, priority: .current)

        let removed = scheduler.yieldQueuedThumbnails()
        XCTAssertEqual(Set(removed.map(\.url)), Set([a, b]))
        XCTAssertTrue(removed.allSatisfy { $0.priority == .thumbnail })
        XCTAssertEqual(scheduler.startNext(runningCount: 0)?.url, viewer)
        XCTAssertNil(scheduler.startNext(runningCount: 0))
    }
}
