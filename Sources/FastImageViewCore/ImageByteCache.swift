import CoreGraphics
import Foundation

public enum CacheBudget {
    public static let thumbnailBytes = 128 * 1024 * 1024
    public static let viewerBytes = 512 * 1024 * 1024
    public static func cost(width: Int, height: Int) -> Int { width * height * 4 }
}

final class CacheBox: NSObject {
    let image: CGImage
    let key: String
    let url: URL

    init(image: CGImage, key: String, url: URL) {
        self.image = image
        self.key = key
        self.url = url
    }
}

public final class ImageByteCache: NSObject, NSCacheDelegate, @unchecked Sendable {
    public let byteLimit: Int
    private let cache = NSCache<NSString, CacheBox>()
    private var keysByURL: [URL: Set<String>] = [:]
    private let lock = NSRecursiveLock()

    public init(byteLimit: Int) {
        self.byteLimit = byteLimit
        super.init()
        cache.totalCostLimit = byteLimit
        cache.delegate = self
    }

    public func insert(url: URL, maxPixelSize: Int, modified: Date, image: CGImage) {
        let key = Self.key(url: url, maxPixelSize: maxPixelSize, modified: modified)
        let cost = CacheBudget.cost(width: image.width, height: image.height)
        let box = CacheBox(image: image, key: key, url: url)
        lock.lock()
        keysByURL[url, default: []].insert(key)
        cache.setObject(box, forKey: key as NSString, cost: cost)
        lock.unlock()
    }

    public func image(url: URL, maxPixelSize: Int, modified: Date) -> CGImage? {
        let key = Self.key(url: url, maxPixelSize: maxPixelSize, modified: modified)
        return cache.object(forKey: key as NSString)?.image
    }

    public func remove(url: URL) {
        lock.lock()
        let keys = keysByURL.removeValue(forKey: url) ?? []
        for key in keys {
            cache.removeObject(forKey: key as NSString)
        }
        lock.unlock()
    }

    public func removeAll() {
        lock.lock()
        keysByURL.removeAll()
        cache.removeAllObjects()
        lock.unlock()
    }

    public func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let box = obj as? CacheBox else { return }
        lock.lock()
        keysByURL[box.url]?.remove(box.key)
        if keysByURL[box.url]?.isEmpty == true {
            keysByURL.removeValue(forKey: box.url)
        }
        lock.unlock()
    }

    private static func key(url: URL, maxPixelSize: Int, modified: Date) -> String {
        "\(url.path)|\(maxPixelSize)|\(modified.timeIntervalSince1970)"
    }
}
