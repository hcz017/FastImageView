import XCTest
@testable import FastImageViewCore

private final class MemoryTrash: TrashStorage {
    var files: Set<String>
    var trashed: [String: String] = [:]
    init(files: Set<String>) { self.files = files }
    func exists(_ url: URL) -> Bool { files.contains(url.path) }
    func trash(at url: URL) throws -> URL {
        guard files.contains(url.path) else { throw CocoaError(.fileNoSuchFile) }
        files.remove(url.path)
        let dest = URL(fileURLWithPath: "/trash/\(url.lastPathComponent)")
        files.insert(dest.path)
        return dest
    }
    func move(from: URL, to: URL) throws {
        guard files.contains(from.path) else { throw CocoaError(.fileNoSuchFile) }
        files.remove(from.path)
        files.insert(to.path)
    }
}

final class DeletionServiceTests: XCTestCase {
    func testRestoreRefusesToOverwrite() throws {
        let original = URL(fileURLWithPath: "/pics/a.jpg")
        let memory = MemoryTrash(files: [original.path])
        let service = DeletionService(storage: memory)
        let trashed = try service.trash(url: original)
        memory.files.insert(original.path)
        XCTAssertThrowsError(try service.restore(trashed)) { error in
            XCTAssertEqual(error as? DeletionError, .destinationOccupied)
        }
        XCTAssertTrue(memory.exists(trashed.trashURL))
    }

    func testRestoreMissingTrash() {
        let item = TrashedFile(originalURL: URL(fileURLWithPath: "/pics/a.jpg"), trashURL: URL(fileURLWithPath: "/trash/a.jpg"))
        let service = DeletionService(storage: MemoryTrash(files: []))
        XCTAssertThrowsError(try service.restore(item)) { error in
            XCTAssertEqual(error as? DeletionError, .trashMissing)
        }
    }

    func testRealTrashRoundTripWhenDesktopExists() throws {
        try XCTSkipUnless(hasDesktopSession(), "无图形会话，跳过废纸篓测试")
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("a.jpg")
        try Data("x".utf8).write(to: file)
        let service = DeletionService(storage: FileManagerTrashStorage())
        let trashed = try service.trash(url: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try service.restore(trashed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try? FileManager.default.removeItem(at: folder)
    }
}
