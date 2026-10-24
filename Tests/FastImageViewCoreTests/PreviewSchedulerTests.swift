import XCTest
@testable import FastImageViewCore

final class PreviewSchedulerTests: XCTestCase {
    func testViewerJumpsAheadOfQueuedThumbnails() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        for index in 0..<6 {
            _ = scheduler.enqueue(url: folder.appendingPathComponent("\(index).jpg"), maxPixelSize: 400, priority: .thumbnail)
        }
        var thumbnails = 0
        while let job = scheduler.startNext(thumbnailRunning: thumbnails, viewerRunning: 0) {
            XCTAssertEqual(job.priority, .thumbnail)
            thumbnails += 1
        }
        XCTAssertEqual(thumbnails, PreviewScheduler.maxConcurrentThumbnails)
        scheduler.yieldQueuedThumbnails()
        let currentURL = folder.appendingPathComponent("current.jpg")
        _ = scheduler.enqueue(url: currentURL, maxPixelSize: 1800, priority: .current)
        _ = scheduler.enqueue(url: folder.appendingPathComponent("side.jpg"), maxPixelSize: 400, priority: .thumbnail)
        let next = scheduler.startNext(
            thumbnailRunning: PreviewScheduler.maxConcurrentThumbnails,
            viewerRunning: 0
        )
        XCTAssertEqual(next?.url, currentURL)
        XCTAssertEqual(next?.priority, .current)
    }

    func testPrefetchBeatsThumbnail() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        _ = scheduler.enqueue(url: folder.appendingPathComponent("t.jpg"), maxPixelSize: 400, priority: .thumbnail)
        let prefetch = folder.appendingPathComponent("p.jpg")
        _ = scheduler.enqueue(url: prefetch, maxPixelSize: 1800, priority: .prefetch)
        XCTAssertEqual(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0)?.url, prefetch)
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

        let wanted: [URL: Int] = [current: 1800, previous: 1800, next: 1800]
        let removed = scheduler.dropQueuedViewerJobs(keeping: wanted)

        XCTAssertEqual(Set(removed.map(\.url)), Set([
            stale,
            folder.appendingPathComponent("old-prefetch.jpg"),
        ]))
        XCTAssertTrue(removed.allSatisfy { $0.priority != .thumbnail })

        let remaining = drain(&scheduler)
        XCTAssertEqual(Set(remaining.map(\.url)), Set([current, previous, next, thumb]))
        XCTAssertTrue(remaining.contains { $0.url == thumb && $0.priority == .thumbnail })
    }

    func testDropQueuedViewerJobsDropsTheOldSizeForTheSameURL() {
        var scheduler = PreviewScheduler()
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        _ = scheduler.enqueue(url: url, maxPixelSize: 1800, priority: .prefetch)
        _ = scheduler.enqueue(url: url, maxPixelSize: 4000, priority: .current)

        let removed = scheduler.dropQueuedViewerJobs(keeping: [url: 4000])
        XCTAssertEqual(removed.map(\.maxPixelSize), [1800])
        XCTAssertEqual(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0)?.maxPixelSize, 4000)
        XCTAssertNil(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0))
    }

    func testNewestThumbnailRunsBeforeOlderOnes() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        let older = folder.appendingPathComponent("older.jpg")
        let newer = folder.appendingPathComponent("newer.jpg")
        _ = scheduler.enqueueThumbnailFirst(url: older, maxPixelSize: 400)
        _ = scheduler.enqueueThumbnailFirst(url: newer, maxPixelSize: 400)
        XCTAssertEqual(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0)?.url, newer)
        XCTAssertEqual(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0)?.url, older)
    }

    func testRepeatedThumbnailRequestMovesItAhead() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        let first = folder.appendingPathComponent("first.jpg")
        let second = folder.appendingPathComponent("second.jpg")
        _ = scheduler.enqueueThumbnailFirst(url: first, maxPixelSize: 400)
        _ = scheduler.enqueueThumbnailFirst(url: second, maxPixelSize: 400)
        _ = scheduler.enqueueThumbnailFirst(url: first, maxPixelSize: 400)
        XCTAssertEqual(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0)?.url, first)
    }

    func testCancelQueuedThumbnailLeavesViewerJob() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        let photo = folder.appendingPathComponent("photo.jpg")
        _ = scheduler.enqueueThumbnailFirst(url: photo, maxPixelSize: 400)
        _ = scheduler.enqueue(url: photo, maxPixelSize: 1800, priority: .current)
        let removed = scheduler.cancelQueuedThumbnails(url: photo)
        XCTAssertEqual(removed.map(\.priority), [.thumbnail])
        XCTAssertEqual(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0)?.priority, .current)
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
        XCTAssertEqual(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0)?.url, viewer)
        XCTAssertNil(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0))
    }

    func testRepeatedViewerRequestKeepsOneJob() {
        var scheduler = PreviewScheduler()
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        let first = scheduler.enqueue(url: url, maxPixelSize: 1800, priority: .prefetch)
        let second = scheduler.enqueue(url: url, maxPixelSize: 1800, priority: .current)
        XCTAssertEqual(first, second)
        XCTAssertEqual(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0)?.priority, .current)
        XCTAssertNil(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0))
    }

    func testCancellingAMiddleThumbnailLeavesTheNewestOrderIntact() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        let old = folder.appendingPathComponent("old.jpg")
        let middle = folder.appendingPathComponent("middle.jpg")
        let newest = folder.appendingPathComponent("newest.jpg")
        _ = scheduler.enqueueThumbnailFirst(url: old, maxPixelSize: 400)
        _ = scheduler.enqueueThumbnailFirst(url: middle, maxPixelSize: 400)
        _ = scheduler.enqueueThumbnailFirst(url: newest, maxPixelSize: 400)

        _ = scheduler.cancelQueuedThumbnails(url: middle)
        XCTAssertEqual(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0)?.url, newest)
        XCTAssertEqual(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0)?.url, old)
        XCTAssertNil(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0))
    }

    func testCancellingManyThumbnailsStillFindsTheLatestOne() {
        var scheduler = PreviewScheduler()
        let folder = URL(fileURLWithPath: "/tmp")
        for index in 0..<100 {
            _ = scheduler.enqueueThumbnailFirst(url: folder.appendingPathComponent("\(index).jpg"), maxPixelSize: 400)
        }
        for index in 0..<99 {
            _ = scheduler.cancelQueuedThumbnails(url: folder.appendingPathComponent("\(index).jpg"))
        }
        XCTAssertEqual(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0)?.url, folder.appendingPathComponent("99.jpg"))
        XCTAssertNil(scheduler.startNext(thumbnailRunning: 0, viewerRunning: 0))
    }

    private func drain(_ scheduler: inout PreviewScheduler) -> [PreviewJob] {
        var jobs: [PreviewJob] = []
        var thumbnails = 0
        var viewers = 0
        while let job = scheduler.startNext(thumbnailRunning: thumbnails, viewerRunning: viewers) {
            jobs.append(job)
            if job.priority == .thumbnail {
                thumbnails += 1
                if thumbnails == PreviewScheduler.maxConcurrentThumbnails { thumbnails = 0 }
            } else {
                viewers += 1
                if viewers == PreviewScheduler.maxConcurrentViewers { viewers = 0 }
            }
        }
        return jobs
    }
}
