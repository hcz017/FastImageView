import Foundation

public struct RecentFolderList: Equatable, Sendable {
    public static let limit = 8
    public static let defaultsKey = "recentFolderPaths"
    public private(set) var paths: [String]

    public init(paths: [String] = []) {
        self.paths = Array(paths.prefix(Self.limit))
    }

    public init(defaults: UserDefaults, key: String = RecentFolderList.defaultsKey) {
        self.init(paths: defaults.stringArray(forKey: key) ?? [])
    }

    public var urls: [URL] {
        paths.map { URL(fileURLWithPath: $0) }
    }

    public mutating func remember(_ url: URL) {
        let path = url.standardizedFileURL.path
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > Self.limit {
            paths.removeLast(paths.count - Self.limit)
        }
    }

    public mutating func remove(_ url: URL) {
        let path = url.standardizedFileURL.path
        paths.removeAll { $0 == path }
    }

    public func save(to defaults: UserDefaults, key: String = RecentFolderList.defaultsKey) {
        defaults.set(paths, forKey: key)
    }
}
