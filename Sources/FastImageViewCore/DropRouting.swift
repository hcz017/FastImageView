import Foundation

public enum DropOpen: Equatable, Sendable {
    case folder(URL)
    case image(URL)
    case images(folder: URL, files: [URL])
}

public enum DropRouting {
    public static func decide(urls: [URL], isDirectory: (URL) -> Bool) -> DropOpen? {
        if let folder = urls.first(where: isDirectory) {
            return .folder(folder)
        }
        let images = urls.filter { !isDirectory($0) && ImageFormat.from(filename: $0.lastPathComponent) != nil }
        guard let first = images.first else { return nil }
        if images.count == 1 { return .image(first) }
        let parents = Set(images.map { parentPath(of: $0) })
        if parents.count == 1, let parent = parents.first {
            return .images(folder: URL(fileURLWithPath: parent), files: images)
        }
        return .image(first)
    }

    private static func parentPath(of url: URL) -> String {
        let path = url.deletingLastPathComponent().standardizedFileURL.path
        if path.count > 1, path.hasSuffix("/") { return String(path.dropLast()) }
        return path
    }
}
