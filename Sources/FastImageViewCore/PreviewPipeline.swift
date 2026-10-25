import CoreGraphics
import Foundation
import ImageIO

public struct ImageIOThumbnailDecoder: Sendable {
    public init() {}

    public func thumbnail(url: URL, maxPixelSize: Int, isRaw: Bool = false) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            ImageIOThumbnailOptions.imageIndex,
            ImageIOThumbnailOptions.dictionary(maxPixelSize: maxPixelSize, isRaw: isRaw) as CFDictionary
        )
    }

    public func longEdge(url: URL) -> Int? {
        pixelSize(url: url).map { max($0.width, $0.height) }
    }

    public func pixelSize(url: URL) -> ImagePixelSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let width = (props[kCGImagePropertyPixelWidth] as? Int)
            ?? (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (props[kCGImagePropertyPixelHeight] as? Int)
            ?? (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        guard let width, let height, width > 0, height > 0 else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? Int)
            ?? (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue
            ?? 1
        return ImagePixelSize.oriented(width: width, height: height, orientation: orientation)
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
    public var onGenerationChange: (() -> Void)?
    public private(set) var generation = 0 {
        didSet { onGenerationChange?() }
    }
    private var scheduler = PreviewScheduler()
    private let thumbnails = ImageByteCache(byteLimit: CacheBudget.thumbnailBytes)
    private let viewers = ImageByteCache(byteLimit: CacheBudget.viewerBytes)
    private let diskThumbnails: ThumbnailDiskStore?
    private let decoder = ImageIOThumbnailDecoder()
    private var runningThumbnails = 0
    private var runningViewers = 0
    private var decodeEpoch = 0
    private var failures = Set<URL>()
    private var viewerPixels: [URL: Int] = [:]
    private var fileDates: [UUID: Date] = [:]
    private var queuedIDsByURL: [URL: Set<UUID>] = [:]
    private var wantedViewerURLs = Set<URL>()
    private var decodingThumbnails = Set<URL>()
    private var generationUpdateScheduled = false

    public init(diskThumbnails: ThumbnailDiskStore? = nil) {
        self.diskThumbnails = diskThumbnails
    }

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
        diskThumbnails?.remove(path: url.path)
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

        let candidates = [current] + [previous, next].compactMap { $0 }
        var wantedPixels: [URL: Int] = [:]
        var jobs: [(file: ImageFile, pixels: Int, priority: PreviewPriority)] = []
        for (index, file) in candidates.enumerated() {
            guard file.iCloudState != .notDownloaded else { continue }
            let pixels = resolvedPixelSize(file: file, requested: maxPixelSize)
            if viewers.image(url: file.url, maxPixelSize: pixels, modified: file.modificationDate) != nil {
                viewerPixels[file.url] = pixels
            } else {
                wantedPixels[file.url] = pixels
                jobs.append((file, pixels, index == 0 ? .current : .prefetch))
            }
        }

        for job in scheduler.dropQueuedViewerJobs(keeping: wantedPixels) {
            untrackQueued(id: job.id, url: job.url)
        }
        wantedViewerURLs = Set(wantedPixels.keys)

        for job in jobs {
            enqueueViewer(job.file, maxPixelSize: job.pixels, priority: job.priority)
        }
        pump()
    }

    public func showCompare(files: [ImageFile], maxPixelSize: Int) {
        for job in scheduler.yieldQueuedThumbnails() {
            untrackQueued(id: job.id, url: job.url)
        }

        var wantedPixels: [URL: Int] = [:]
        var jobs: [(file: ImageFile, pixels: Int)] = []
        for file in files {
            guard file.iCloudState != .notDownloaded else { continue }
            let pixels = resolvedPixelSize(file: file, requested: maxPixelSize)
            if viewers.image(url: file.url, maxPixelSize: pixels, modified: file.modificationDate) != nil {
                viewerPixels[file.url] = pixels
            } else {
                wantedPixels[file.url] = pixels
                jobs.append((file, pixels))
            }
        }

        for job in scheduler.dropQueuedViewerJobs(keeping: wantedPixels) {
            untrackQueued(id: job.id, url: job.url)
        }
        wantedViewerURLs = Set(wantedPixels.keys)

        for job in jobs {
            enqueueViewer(job.file, maxPixelSize: job.pixels, priority: .current)
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
        guard viewers.image(url: file.url, maxPixelSize: maxPixelSize, modified: file.modificationDate) == nil else {
            viewerPixels[file.url] = maxPixelSize
            return
        }
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
        while let job = scheduler.startNext(thumbnailRunning: runningThumbnails, viewerRunning: runningViewers) {
            if job.priority == .thumbnail { runningThumbnails += 1 } else { runningViewers += 1 }
            let modified = fileDates[job.id] ?? .distantPast
            untrackQueued(id: job.id, url: job.url)
            let priority = job.priority
            let epoch = decodeEpoch
            let disk = diskThumbnails
            let path = job.url.path
            if priority == .thumbnail { decodingThumbnails.insert(job.url) }
            Task.detached { [decoder] in
                let image: CGImage?
                var loadedFromDisk = false
                let isRaw = ImageFormat.from(filename: job.url.lastPathComponent)?.isRaw ?? false
                if priority == .thumbnail,
                   let disk,
                   let cached = disk.image(path: path, maxPixelSize: job.maxPixelSize, modified: modified) {
                    image = cached
                    loadedFromDisk = true
                } else {
                    image = decoder.thumbnail(url: job.url, maxPixelSize: job.maxPixelSize, isRaw: isRaw)
                }
                if priority == .thumbnail, let image, !loadedFromDisk, FileManager.default.fileExists(atPath: path) {
                    disk?.store(path: path, maxPixelSize: job.maxPixelSize, modified: modified, image: image)
                }
                await MainActor.run {
                    if priority == .thumbnail {
                        self.runningThumbnails -= 1
                        self.decodingThumbnails.remove(job.url)
                    } else {
                        self.runningViewers -= 1
                    }
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
                        self.scheduleGenerationUpdate()
                    }
                    self.pump()
                }
            }
        }
    }

    /// 一批解码完成只触发一次 SwiftUI 重绘，避免整屏 cell 随每张图重复重算。
    private func scheduleGenerationUpdate() {
        guard !generationUpdateScheduled else { return }
        generationUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.generationUpdateScheduled = false
                self.generation += 1
            }
        }
    }
}
