import Foundation

public struct CopySet: Equatable, Sendable {
    public var imageURL: URL
    public var paths: [String]

    public init(imageURL: URL, paths: [String]) {
        self.imageURL = imageURL
        self.paths = paths
    }

    public var filenames: [String] {
        paths.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    public var urls: [URL] {
        paths.map { URL(fileURLWithPath: $0) }
    }
}

public enum CopyRouting {
    /// 右键点在多选内时，路径/文件名/文件拷贝覆盖整个选区；图片位图仍以点击项为主。
    public static func make(clicked: URL, orderedSelection: [URL]) -> CopySet {
        let source = orderedSelection.contains(clicked) && orderedSelection.count > 1 ? orderedSelection : [clicked]
        return CopySet(imageURL: clicked, paths: source.map(\.path))
    }
}
