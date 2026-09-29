import XCTest
@testable import FastImageViewCore

final class FolderScannerTests: XCTestCase {
    func testScansOnlyCurrentLevelImagesInNaturalOrder() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("notes.txt"))
        try Data().write(to: root.appendingPathComponent("IMG_10.jpg"))
        try Data().write(to: root.appendingPathComponent("IMG_2.JPG"))
        try Data().write(to: root.appendingPathComponent(".hidden.png"))
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data().write(to: sub.appendingPathComponent("nested.jpg"))

        let files = try FolderScanner().scan(folder: root)
        XCTAssertEqual(files.map(\.filename), ["IMG_2.JPG", "IMG_10.jpg"])
        XCTAssertEqual(files.map(\.format), [.jpeg, .jpeg])
        XCTAssertEqual(files.map(\.iCloudState), [.notCloud, .notCloud])
    }
}
