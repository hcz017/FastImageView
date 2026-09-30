import CoreGraphics
import Foundation

public enum CacheBudget {
    public static let thumbnailBytes = 128 * 1024 * 1024
    public static let viewerBytes = 512 * 1024 * 1024
    public static func cost(width: Int, height: Int) -> Int { width * height * 4 }
}

final class CacheBox: NSObject {
    let image: CGImage
    init(image: CGImage) { self.image = image }
}

public final class ImageByteCache: @unchecked Sendable {
    public let byteLimit: Int
    private let cache = NSCache<NSString, CacheBox>()
    private var keysByURL: [URL: Set<String>] = [:]
    private let lock = NSLock()

    public init(byteLimit: Int) {
        self.byteLimit = byteLimit
        cache.totalCostLimit = byteLimit
    }

    public func insert(url: URL, maxPixelSize: Int, modified: Date, image: CGImage) {
        let key = Self.key(url: url, maxPixelSize: maxPixelSize, modified: modified)
        cache.setObject(CacheBox(image: image), forKey: key as NSString, cost: CacheBudget.cost(width: image.width, height: image.height))
        lock.lock()
        keysByURL[url, default: []].insert(key)
        lock.unlock()
    }

    public func image(url: URL, maxPixelSize: Int, modified: Date) -> CGImage? {
        let key = Self.key(url: url, maxPixelSize: maxPixelSize, modified: modified)
        return cache.object(forKey: key as NSString)?.image
    }

    public func remove(url: URL) {
        lock.lock()
        let keys = keysByURL.removeValue(forKey: url) ?? []
        lock.unlock()
        for key in keys { cache.removeObject(forKey: key as NSString) }
    }

    public func removeAll() {
        lock.lock()
        keysByURL.removeAll()
        lock.unlock()
        cache.removeAllObjects()
    }

    private static func key(url: URL, maxPixelSize: Int, modified: Date) -> String {
        "\(url.path)|\(maxPixelSize)|\(modified.timeIntervalSince1970)"
    }
}
