import CoreGraphics
import Foundation
import ImageIO

public struct ImageIOThumbnailDecoder: Sendable {
    public init() {}

    public func thumbnail(url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            ImageIOThumbnailOptions.imageIndex,
            ImageIOThumbnailOptions.dictionary(maxPixelSize: maxPixelSize) as CFDictionary
        )
    }

    public func longEdge(url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return max(width, height)
    }
}

/// Pure write/drop decision for completed decode jobs (epoch + wanted viewer URLs).
public struct PreviewDecodeWriteDecision: Equatable, Sendable {
    public var shouldWrite: Bool

    public init(shouldWrite: Bool) {
        self.shouldWrite = shouldWrite
    }

    public static func decide(
        jobEpoch: Int,
        currentEpoch: Int,
        priority: PreviewPriority,
        url: URL,
        wantedViewerURLs: Set<URL>
    ) -> PreviewDecodeWriteDecision {
        guard jobEpoch == currentEpoch else {
            return PreviewDecodeWriteDecision(shouldWrite: false)
        }
        if priority == .thumbnail {
            return PreviewDecodeWriteDecision(shouldWrite: true)
        }
        return PreviewDecodeWriteDecision(shouldWrite: wantedViewerURLs.contains(url))
    }
}

@MainActor
public final class LivePreviewPipeline: PreviewPipeline {
    public private(set) var generation = 0
    private var scheduler = PreviewScheduler()
    private let thumbnails = ImageByteCache(byteLimit: CacheBudget.thumbnailBytes)
    private let viewers = ImageByteCache(byteLimit: CacheBudget.viewerBytes)
    private let decoder = ImageIOThumbnailDecoder()
    private var running = 0
    private var decodeEpoch = 0
    private var failures = Set<URL>()
    private var viewerPixels: [URL: Int] = [:]
    private var fileDates: [UUID: Date] = [:]
    private var queuedIDsByURL: [URL: Set<UUID>] = [:]
    private var wantedViewerURLs = Set<URL>()
    private var decodingThumbnails = Set<URL>()

    public init() {}

    public func reset() {
        scheduler = PreviewScheduler()
        thumbnails.removeAll()
        viewers.removeAll()
        failures.removeAll()
        viewerPixels.removeAll()
        fileDates.removeAll()
        queuedIDsByURL.removeAll()
        wantedViewerURLs.removeAll()
        decodeEpoch += 1
        generation += 1
    }

    public func cancel(url: URL) {
        scheduler.cancel(url: url)
        thumbnails.remove(url: url)
        viewers.remove(url: url)
        viewerPixels.removeValue(forKey: url)
        failures.remove(url)
        if let ids = queuedIDsByURL.removeValue(forKey: url) {
            for id in ids {
                fileDates.removeValue(forKey: id)
            }
        }
    }

    public func requestThumbnail(file: ImageFile) {
        guard file.iCloudState != .notDownloaded else { return }
        guard !failures.contains(file.url) else { return }
        if thumbnails.image(url: file.url, maxPixelSize: PreviewMaxPixel.thumbnail, modified: file.modificationDate) != nil { return }
        if decodingThumbnails.contains(file.url) { return }
        if queuedIDsByURL[file.url] != nil {
            _ = scheduler.enqueueThumbnailFirst(url: file.url, maxPixelSize: PreviewMaxPixel.thumbnail)
            return
        }
        let id = scheduler.enqueueThumbnailFirst(url: file.url, maxPixelSize: PreviewMaxPixel.thumbnail)
        remember(file, id: id)
        pump()
    }

    public func cancelQueuedThumbnail(url: URL) {
        for job in scheduler.cancelQueuedThumbnails(url: url) {
            untrackQueued(id: job.id, url: job.url)
        }
    }

    public func showViewer(current: ImageFile, previous: ImageFile?, next: ImageFile?, maxPixelSize: Int) {
        for job in scheduler.yieldQueuedThumbnails() {
            untrackQueued(id: job.id, url: job.url)
        }

        var wanted: Set<URL> = [current.url]
        if let previous { wanted.insert(previous.url) }
        if let next { wanted.insert(next.url) }

        for job in scheduler.dropQueuedViewerJobs(keeping: wanted) {
            untrackQueued(id: job.id, url: job.url)
        }
        wantedViewerURLs = wanted

        enqueueViewer(current, maxPixelSize: resolvedPixelSize(file: current, requested: maxPixelSize), priority: .current)
        if let previous {
            enqueueViewer(previous, maxPixelSize: resolvedPixelSize(file: previous, requested: maxPixelSize), priority: .prefetch)
        }
        if let next {
            enqueueViewer(next, maxPixelSize: resolvedPixelSize(file: next, requested: maxPixelSize), priority: .prefetch)
        }
        pump()
    }

    public func cachedThumbnail(file: ImageFile) -> CGImage? {
        thumbnails.image(url: file.url, maxPixelSize: PreviewMaxPixel.thumbnail, modified: file.modificationDate)
    }

    public func cachedViewerImage(file: ImageFile) -> CGImage? {
        guard let pixels = viewerPixels[file.url] else { return nil }
        return viewers.image(url: file.url, maxPixelSize: pixels, modified: file.modificationDate)
    }

    public func didFail(url: URL) -> Bool { failures.contains(url) }

    private func remember(_ file: ImageFile, id: UUID) {
        trackQueued(id: id, url: file.url, modified: file.modificationDate)
    }

    private func enqueueViewer(_ file: ImageFile, maxPixelSize: Int, priority: PreviewPriority) {
        guard file.iCloudState != .notDownloaded else { return }
        let id = scheduler.enqueue(url: file.url, maxPixelSize: maxPixelSize, priority: priority)
        trackQueued(id: id, url: file.url, modified: file.modificationDate)
    }

    private func trackQueued(id: UUID, url: URL, modified: Date) {
        fileDates[id] = modified
        queuedIDsByURL[url, default: []].insert(id)
    }

    private func untrackQueued(id: UUID, url: URL) {
        fileDates.removeValue(forKey: id)
        queuedIDsByURL[url]?.remove(id)
        if queuedIDsByURL[url]?.isEmpty == true {
            queuedIDsByURL.removeValue(forKey: url)
        }
    }

    private func resolvedPixelSize(file: ImageFile, requested: Int) -> Int {
        guard !file.format.isRaw, requested == PreviewMaxPixel.rawActualCap else { return requested }
        guard let edge = decoder.longEdge(url: file.url) else { return requested }
        return min(edge, PreviewMaxPixel.rawActualCap)
    }

    private func pump() {
        while let job = scheduler.startNext(runningCount: running) {
            running += 1
            let modified = fileDates[job.id] ?? .distantPast
            untrackQueued(id: job.id, url: job.url)
            let priority = job.priority
            let epoch = decodeEpoch
            if priority == .thumbnail { decodingThumbnails.insert(job.url) }
            Task.detached { [decoder] in
                let image = decoder.thumbnail(url: job.url, maxPixelSize: job.maxPixelSize)
                await MainActor.run {
                    self.running -= 1
                    if priority == .thumbnail { self.decodingThumbnails.remove(job.url) }
                    let decision = PreviewDecodeWriteDecision.decide(
                        jobEpoch: epoch,
                        currentEpoch: self.decodeEpoch,
                        priority: priority,
                        url: job.url,
                        wantedViewerURLs: self.wantedViewerURLs
                    )
                    if decision.shouldWrite {
                        if let image {
                            let cache = priority == .thumbnail ? self.thumbnails : self.viewers
                            cache.insert(url: job.url, maxPixelSize: job.maxPixelSize, modified: modified, image: image)
                            if priority != .thumbnail { self.viewerPixels[job.url] = job.maxPixelSize }
                        } else {
                            self.failures.insert(job.url)
                        }
                        self.generation += 1
                    }
                    self.pump()
                }
            }
        }
    }
}
