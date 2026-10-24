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

    /// 缩略图按请求时间追加，取任务时从尾部弹出，天然是“最新请求优先”。
    /// 中间被取消或替换的任务留成 nil 占位，避免每次删除都搬动整个数组。
    private var thumbnailJobs: [PreviewJob?] = []
    private var thumbnailIndex: [UUID: Int] = [:]
    private var thumbnailIDByURL: [URL: UUID] = [:]
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
        if let id = thumbnailIDByURL[url] {
            removeThumbnail(id: id)
            let job = PreviewJob(id: id, url: url, maxPixelSize: maxPixelSize, priority: .thumbnail)
            appendThumbnail(job)
            return id
        }
        let job = PreviewJob(id: UUID(), url: url, maxPixelSize: maxPixelSize, priority: .thumbnail)
        appendThumbnail(job)
        return job.id
    }

    private mutating func appendThumbnail(_ job: PreviewJob) {
        thumbnailIndex[job.id] = thumbnailJobs.count
        thumbnailJobs.append(job)
        thumbnailIDByURL[job.url] = job.id
    }

    private mutating func removeThumbnail(id: UUID) {
        guard let index = thumbnailIndex.removeValue(forKey: id),
              let job = thumbnailJobs[index] else { return }
        thumbnailJobs[index] = nil
        if thumbnailIDByURL[job.url] == id {
            thumbnailIDByURL.removeValue(forKey: job.url)
        }
        compactThumbnailJobsIfNeeded()
    }

    private mutating func popThumbnail() -> PreviewJob? {
        while let candidate = thumbnailJobs.popLast() {
            guard let job = candidate else { continue }
            thumbnailIndex.removeValue(forKey: job.id)
            if thumbnailIDByURL[job.url] == job.id {
                thumbnailIDByURL.removeValue(forKey: job.url)
            }
            return job
        }
        return nil
    }

    private mutating func compactThumbnailJobsIfNeeded() {
        guard thumbnailJobs.count > 64, thumbnailJobs.count > thumbnailIndex.count * 2 else { return }
        let compacted: [PreviewJob] = thumbnailJobs.compactMap { $0 }
        thumbnailJobs = compacted
        thumbnailIndex.removeAll(keepingCapacity: true)
        for (index, job) in compacted.enumerated() {
            thumbnailIndex[job.id] = index
        }
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
        guard let id = thumbnailIDByURL[url],
              let index = thumbnailIndex[id],
              let job = thumbnailJobs[index] else { return [] }
        removeThumbnail(id: id)
        return [job]
    }

    @discardableResult
    public mutating func yieldQueuedThumbnails() -> [PreviewJob] {
        let removed = thumbnailJobs.compactMap { $0 }
        thumbnailJobs.removeAll(keepingCapacity: true)
        thumbnailIndex.removeAll(keepingCapacity: true)
        thumbnailIDByURL.removeAll(keepingCapacity: true)
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
        if let id = thumbnailIDByURL[url] {
            removeThumbnail(id: id)
        }
        currentViewers.removeAll { $0.url == url }
        prefetchViewers.removeAll { $0.url == url }
    }

    public mutating func startNext(thumbnailRunning: Int, viewerRunning: Int) -> PreviewJob? {
        if viewerRunning < Self.maxConcurrentViewers, let job = popViewer() {
            return job
        }
        if thumbnailRunning < Self.maxConcurrentThumbnails, let job = popThumbnail() {
            return job
        }
        return nil
    }

    private mutating func popViewer() -> PreviewJob? {
        if !currentViewers.isEmpty { return currentViewers.removeFirst() }
        if !prefetchViewers.isEmpty { return prefetchViewers.removeFirst() }
        return nil
    }
}
