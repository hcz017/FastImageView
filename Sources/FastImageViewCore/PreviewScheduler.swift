import Foundation

public enum PreviewPriority: Int, Equatable, Sendable {
    case thumbnail = 0
    case prefetch = 1
    case current = 2
}

public struct PreviewJob: Equatable, Sendable {
    public var id: UUID
    public var url: URL
    public var maxPixelSize: Int
    public var priority: PreviewPriority
}

public struct PreviewScheduler: Equatable, Sendable {
    /// 缩略图与查看器分开排队，查看器不会排在已经开始的缩略图后面。
    public static let maxConcurrentThumbnails = 4
    public static let maxConcurrentViewers = 2

    private var thumbnails: [PreviewJob] = []
    private var currentViewers: [PreviewJob] = []
    private var prefetchViewers: [PreviewJob] = []

    public init() {}

    @discardableResult
    public mutating func enqueue(url: URL, maxPixelSize: Int, priority: PreviewPriority) -> UUID {
        if priority == .thumbnail {
            return enqueueThumbnail(url: url, maxPixelSize: maxPixelSize)
        }
        return enqueueViewer(url: url, maxPixelSize: maxPixelSize, priority: priority)
    }

    /// Puts this thumbnail ahead of other queued thumbnails. A second request for the same URL moves the existing job forward.
    @discardableResult
    public mutating func enqueueThumbnailFirst(url: URL, maxPixelSize: Int) -> UUID {
        enqueueThumbnail(url: url, maxPixelSize: maxPixelSize)
    }

    private mutating func enqueueThumbnail(url: URL, maxPixelSize: Int) -> UUID {
        if let index = thumbnails.firstIndex(where: { $0.url == url }) {
            var job = thumbnails.remove(at: index)
            job.maxPixelSize = maxPixelSize
            thumbnails.insert(job, at: 0)
            return job.id
        }
        let job = PreviewJob(id: UUID(), url: url, maxPixelSize: maxPixelSize, priority: .thumbnail)
        thumbnails.insert(job, at: 0)
        return job.id
    }

    private mutating func enqueueViewer(url: URL, maxPixelSize: Int, priority: PreviewPriority) -> UUID {
        if let index = currentViewers.firstIndex(where: { $0.url == url && $0.maxPixelSize == maxPixelSize }) {
            var job = currentViewers.remove(at: index)
            job.priority = priority
            placeViewer(job)
            return job.id
        }
        if let index = prefetchViewers.firstIndex(where: { $0.url == url && $0.maxPixelSize == maxPixelSize }) {
            var job = prefetchViewers.remove(at: index)
            job.priority = priority
            placeViewer(job)
            return job.id
        }
        let job = PreviewJob(id: UUID(), url: url, maxPixelSize: maxPixelSize, priority: priority)
        placeViewer(job)
        return job.id
    }

    private mutating func placeViewer(_ job: PreviewJob) {
        if job.priority == .current {
            currentViewers.insert(job, at: 0)
        } else {
            prefetchViewers.insert(job, at: 0)
        }
    }

    @discardableResult
    public mutating func cancelQueuedThumbnails(url: URL) -> [PreviewJob] {
        let removed = thumbnails.filter { $0.url == url }
        thumbnails.removeAll { $0.url == url }
        return removed
    }

    @discardableResult
    public mutating func yieldQueuedThumbnails() -> [PreviewJob] {
        let removed = thumbnails
        thumbnails.removeAll()
        return removed
    }

    /// Drops queued viewer jobs that are no longer wanted at their decoded size.
    @discardableResult
    public mutating func dropQueuedViewerJobs(keeping wanted: [URL: Int]) -> [PreviewJob] {
        let removedCurrent = currentViewers.filter { wanted[$0.url] != $0.maxPixelSize }
        let removedPrefetch = prefetchViewers.filter { wanted[$0.url] != $0.maxPixelSize }
        currentViewers.removeAll { wanted[$0.url] != $0.maxPixelSize }
        prefetchViewers.removeAll { wanted[$0.url] != $0.maxPixelSize }
        return removedCurrent + removedPrefetch
    }

    public mutating func cancel(url: URL) {
        thumbnails.removeAll { $0.url == url }
        currentViewers.removeAll { $0.url == url }
        prefetchViewers.removeAll { $0.url == url }
    }

    public mutating func startNext(thumbnailRunning: Int, viewerRunning: Int) -> PreviewJob? {
        if viewerRunning < Self.maxConcurrentViewers, let job = popViewer() {
            return job
        }
        if thumbnailRunning < Self.maxConcurrentThumbnails, !thumbnails.isEmpty {
            return thumbnails.removeFirst()
        }
        return nil
    }

    private mutating func popViewer() -> PreviewJob? {
        if !currentViewers.isEmpty { return currentViewers.removeFirst() }
        if !prefetchViewers.isEmpty { return prefetchViewers.removeFirst() }
        return nil
    }
}
