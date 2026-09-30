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

@MainActor
public final class LivePreviewPipeline: PreviewPipeline {
    public private(set) var generation = 0
    private var scheduler = PreviewScheduler()
    private let thumbnails = ImageByteCache(byteLimit: CacheBudget.thumbnailBytes)
    private let viewers = ImageByteCache(byteLimit: CacheBudget.viewerBytes)
    private let decoder = ImageIOThumbnailDecoder()
    private var running = 0
    private var failures = Set<URL>()
    private var jobs: [UUID: PreviewJob] = [:]
    private var viewerPixels: [URL: Int] = [:]

    public init() {}

    public func reset() {
        scheduler = PreviewScheduler()
        thumbnails.removeAll()
        viewers.removeAll()
        failures.removeAll()
        jobs.removeAll()
        viewerPixels.removeAll()
        generation += 1
    }

    public func cancel(url: URL) {
        scheduler.cancel(url: url)
        thumbnails.remove(url: url)
        viewers.remove(url: url)
        viewerPixels.removeValue(forKey: url)
        failures.remove(url)
    }

    public func requestThumbnail(file: ImageFile) {
        guard file.iCloudState != .notDownloaded else { return }
        guard !failures.contains(file.url) else { return }
        if thumbnails.image(url: file.url, maxPixelSize: PreviewMaxPixel.thumbnail, modified: file.modificationDate) != nil { return }
        let id = scheduler.enqueue(url: file.url, maxPixelSize: PreviewMaxPixel.thumbnail, priority: .thumbnail)
        jobs[id] = PreviewJob(id: id, url: file.url, maxPixelSize: PreviewMaxPixel.thumbnail, priority: .thumbnail)
        remember(file, maxPixelSize: PreviewMaxPixel.thumbnail, id: id)
        pump()
    }

    public func showViewer(current: ImageFile, previous: ImageFile?, next: ImageFile?, maxPixelSize: Int) {
        scheduler.yieldQueuedThumbnails()
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

    private var fileDates: [UUID: Date] = [:]

    private func remember(_ file: ImageFile, maxPixelSize: Int, id: UUID) {
        fileDates[id] = file.modificationDate
        jobs[id] = PreviewJob(id: id, url: file.url, maxPixelSize: maxPixelSize, priority: jobs[id]?.priority ?? .thumbnail)
    }

    private func enqueueViewer(_ file: ImageFile, maxPixelSize: Int, priority: PreviewPriority) {
        guard file.iCloudState != .notDownloaded else { return }
        let id = scheduler.enqueue(url: file.url, maxPixelSize: maxPixelSize, priority: priority)
        jobs[id] = PreviewJob(id: id, url: file.url, maxPixelSize: maxPixelSize, priority: priority)
        fileDates[id] = file.modificationDate
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
            let priority = job.priority
            Task.detached { [decoder] in
                let image = decoder.thumbnail(url: job.url, maxPixelSize: job.maxPixelSize)
                await MainActor.run {
                    self.running -= 1
                    if let image {
                        let cache = priority == .thumbnail ? self.thumbnails : self.viewers
                        cache.insert(url: job.url, maxPixelSize: job.maxPixelSize, modified: modified, image: image)
                        if priority != .thumbnail { self.viewerPixels[job.url] = job.maxPixelSize }
                    } else {
                        self.failures.insert(job.url)
                    }
                    self.generation += 1
                    self.pump()
                }
            }
        }
    }
}
