import CoreGraphics
import Foundation

public struct TrashedFile: Equatable, Sendable {
    public var originalURL: URL
    public var trashURL: URL
    public init(originalURL: URL, trashURL: URL) {
        self.originalURL = originalURL
        self.trashURL = trashURL
    }
}

public enum DeletionError: Error, Equatable, LocalizedError {
    case missing
    case destinationOccupied
    case trashMissing
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .missing: return "文件已经不存在"
        case .destinationOccupied: return "原路径已有文件，没有覆盖"
        case .trashMissing: return "废纸篓里的文件已经不在"
        case .message(let text): return text
        }
    }
}

public protocol TrashStorage {
    func exists(_ url: URL) -> Bool
    func trash(at url: URL) throws -> URL
    func move(from: URL, to: URL) throws
}

public struct DeletionService {
    public var storage: any TrashStorage
    public init(storage: any TrashStorage) { self.storage = storage }

    public func trash(url: URL) throws -> TrashedFile {
        do {
            let trashed = try storage.trash(at: url)
            return TrashedFile(originalURL: url, trashURL: trashed)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            throw DeletionError.missing
        } catch let error as DeletionError {
            throw error
        } catch {
            throw DeletionError.message(error.localizedDescription)
        }
    }

    public func restore(_ item: TrashedFile) throws {
        if storage.exists(item.originalURL) { throw DeletionError.destinationOccupied }
        if !storage.exists(item.trashURL) { throw DeletionError.trashMissing }
        do {
            try storage.move(from: item.trashURL, to: item.originalURL)
        } catch {
            throw DeletionError.message(error.localizedDescription)
        }
    }
}

public struct FileManagerTrashStorage: TrashStorage {
    public init() {}
    public func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    public func trash(at url: URL) throws -> URL {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        guard let trashed = resulting as URL? else { throw DeletionError.message("废纸篓没有返回新路径") }
        return trashed
    }
    public func move(from: URL, to: URL) throws {
        try FileManager.default.moveItem(at: from, to: to)
    }
}

public func hasDesktopSession() -> Bool {
    CGSessionCopyCurrentDictionary() != nil
}
