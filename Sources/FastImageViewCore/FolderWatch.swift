import Darwin
import Foundation

public protocol FolderWatching: AnyObject {
    func start(folder: URL, handler: @escaping @Sendable () -> Void)
    func stop()
}

public final class IdleFolderWatch: FolderWatching {
    public init() {}
    public func start(folder: URL, handler: @escaping @Sendable () -> Void) {}
    public func stop() {}
}

public final class DispatchFolderWatch: FolderWatching, @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?

    public init() {}

    public func start(folder: URL, handler: @escaping @Sendable () -> Void) {
        stop()
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
    }
}

enum FileIdentity {
    static func byPath(_ files: [ImageFile]) -> [String: String] {
        var map: [String: String] = [:]
        for file in files {
            guard let token = token(for: file.url) else { continue }
            map[file.url.standardizedFileURL.path] = token
        }
        return map
    }

    static func token(for url: URL) -> String? {
        guard let id = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else {
            return nil
        }
        return String(describing: id)
    }
}
