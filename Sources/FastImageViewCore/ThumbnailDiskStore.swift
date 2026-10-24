import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

public enum ThumbnailDiskKey {
    public static func make(path: String, maxPixelSize: Int, modified: Date) -> String {
        let token = "\(path)|\(maxPixelSize)|\(modified.timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct ThumbnailDiskRecord: Equatable, Codable, Sendable {
    public var fileName: String
    public var bytes: Int
    public var lastAccess: Date
    public var sourcePath: String
}

/// Which thumbnail files stay on disk when the folder is over its byte cap.
public struct ThumbnailDiskIndex: Equatable, Codable, Sendable {
    public var byteLimit: Int
    public private(set) var records: [String: ThumbnailDiskRecord]

    public init(byteLimit: Int, records: [String: ThumbnailDiskRecord] = [:]) {
        self.byteLimit = byteLimit
        self.records = records
    }

    public var totalBytes: Int {
        records.values.reduce(0) { $0 + $1.bytes }
    }

    /// Remembers a file and returns the filenames of older files that no longer fit.
    /// The file just written stays even when it alone is larger than the cap.
    public mutating func remember(
        key: String,
        fileName: String,
        bytes: Int,
        sourcePath: String,
        at date: Date
    ) -> [String] {
        records[key] = ThumbnailDiskRecord(
            fileName: fileName,
            bytes: bytes,
            lastAccess: date,
            sourcePath: sourcePath
        )
        return evict(protecting: key)
    }

    public mutating func touch(key: String, at date: Date) {
        guard var record = records[key] else { return }
        record.lastAccess = date
        records[key] = record
    }

    public mutating func removeSource(_ path: String) -> [String] {
        let matches = records.filter { $0.value.sourcePath == path }
        for key in matches.keys {
            records.removeValue(forKey: key)
        }
        return matches.values.map(\.fileName)
    }

    public mutating func remove(key: String) -> String? {
        let fileName = records[key]?.fileName
        records.removeValue(forKey: key)
        return fileName
    }

    private mutating func evict(protecting protected: String) -> [String] {
        var removed: [String] = []
        while totalBytes > byteLimit {
            let victims = records.filter { $0.key != protected }
            guard let oldest = victims.min(by: { lhs, rhs in
                if lhs.value.lastAccess == rhs.value.lastAccess {
                    return lhs.key < rhs.key
                }
                return lhs.value.lastAccess < rhs.value.lastAccess
            }) else { break }
            removed.append(oldest.value.fileName)
            records.removeValue(forKey: oldest.key)
        }
        return removed
    }
}

/// JPEG thumbnails under ~/Library/Caches. Switching folders clears memory only.
public final class ThumbnailDiskStore: @unchecked Sendable {
    public static let byteLimit = CacheBudget.thumbnailDiskBytes
    private static let indexName = "index.json"
    private static let flushEveryReads = 32

    public let directory: URL
    private let lock = NSLock()
    private var index: ThumbnailDiskIndex
    private let indexURL: URL
    private var readsSinceFlush = 0

    public init(directory: URL, byteLimit: Int = ThumbnailDiskStore.byteLimit) throws {
        self.directory = directory
        self.indexURL = directory.appendingPathComponent(Self.indexName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           var loaded = try? JSONDecoder().decode(ThumbnailDiskIndex.self, from: data) {
            loaded.byteLimit = byteLimit
            index = loaded
        } else {
            index = ThumbnailDiskIndex(byteLimit: byteLimit)
        }
        reconcileLocked()
    }

    public static func liveDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return caches.appendingPathComponent("local.FastImageView/Thumbnails", isDirectory: true)
    }

    public static func live() -> ThumbnailDiskStore? {
        try? ThumbnailDiskStore(directory: liveDirectory())
    }

    public func image(path: String, maxPixelSize: Int, modified: Date) -> CGImage? {
        let key = ThumbnailDiskKey.make(path: path, maxPixelSize: maxPixelSize, modified: modified)
        lock.lock()
        guard let record = index.records[key] else {
            lock.unlock()
            return nil
        }
        let fileURL = directory.appendingPathComponent(record.fileName)
        index.touch(key: key, at: Date())
        readsSinceFlush += 1
        let shouldFlush = readsSinceFlush >= Self.flushEveryReads
        if shouldFlush { readsSinceFlush = 0 }
        lock.unlock()

        if shouldFlush {
            lock.lock()
            persistLocked()
            lock.unlock()
        }

        // ImageIO 解码放在锁外，否则磁盘命中的缩略图会被这个锁串行化。
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            invalidate(key: key)
            return nil
        }
        return image
    }

    public func store(path: String, maxPixelSize: Int, modified: Date, image: CGImage) {
        guard let data = ThumbnailJPEG.data(from: image) else { return }
        let key = ThumbnailDiskKey.make(path: path, maxPixelSize: maxPixelSize, modified: modified)
        let fileName = key + ".jpg"
        let fileURL = directory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
        lock.lock()
        let doomed = index.remember(
            key: key,
            fileName: fileName,
            bytes: data.count,
            sourcePath: path,
            at: Date()
        )
        persistLocked()
        readsSinceFlush = 0
        lock.unlock()
        let files = FileManager.default
        for name in doomed where name != fileName {
            try? files.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    public func remove(path: String) {
        lock.lock()
        let names = index.removeSource(path)
        if !names.isEmpty { persistLocked() }
        lock.unlock()
        guard !names.isEmpty else { return }
        let files = FileManager.default
        for name in names {
            try? files.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func invalidate(key: String) {
        lock.lock()
        let fileName = index.remove(key: key)
        if fileName != nil { persistLocked() }
        lock.unlock()
        if let fileName {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
        }
    }

    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        persistLocked()
        readsSinceFlush = 0
    }

    private func reconcileLocked() {
        let files = FileManager.default
        let existing = Set((try? files.contentsOfDirectory(atPath: directory.path)) ?? [])
        let missing = index.records.keys.filter { key in
            !existing.contains(index.records[key]?.fileName ?? "")
        }
        var changed = false
        for key in missing {
            _ = index.remove(key: key)
            changed = true
        }
        let known = Set(index.records.values.map(\.fileName))
        for name in existing where name != Self.indexName && !known.contains(name) {
            try? files.removeItem(at: directory.appendingPathComponent(name))
        }
        if changed { persistLocked() }
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

private enum ThumbnailJPEG {
    static func data(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
