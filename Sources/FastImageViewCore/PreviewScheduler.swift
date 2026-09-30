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
    public static let maxConcurrent = 4
    private var queue: [PreviewJob] = []

    public init() {}

    @discardableResult
    public mutating func enqueue(url: URL, maxPixelSize: Int, priority: PreviewPriority) -> UUID {
        let job = PreviewJob(id: UUID(), url: url, maxPixelSize: maxPixelSize, priority: priority)
        queue.append(job)
        return job.id
    }

    @discardableResult
    public mutating func yieldQueuedThumbnails() -> [PreviewJob] {
        let removed = queue.filter { $0.priority == .thumbnail }
        queue.removeAll { $0.priority == .thumbnail }
        return removed
    }

    @discardableResult
    public mutating func dropQueuedViewerJobs(keeping urls: Set<URL>) -> [PreviewJob] {
        let removed = queue.filter { $0.priority != .thumbnail && !urls.contains($0.url) }
        queue.removeAll { $0.priority != .thumbnail && !urls.contains($0.url) }
        return removed
    }

    public mutating func cancel(url: URL) {
        queue.removeAll { $0.url == url }
    }

    public mutating func startNext(runningCount: Int) -> PreviewJob? {
        guard runningCount < Self.maxConcurrent, !queue.isEmpty else { return nil }
        let index = queue.indices.max { lhs, rhs in
            let left = queue[lhs]
            let right = queue[rhs]
            if left.priority.rawValue == right.priority.rawValue { return lhs > rhs }
            return left.priority.rawValue < right.priority.rawValue
        }
        guard let index else { return nil }
        return queue.remove(at: index)
    }
}
