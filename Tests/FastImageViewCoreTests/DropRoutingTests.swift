import XCTest
@testable import FastImageViewCore

final class DropRoutingTests: XCTestCase {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    func testFolderWinsOverImagesDroppedWithIt() {
        let decision = DropRouting.decide(
            urls: [url("/pics/a.jpg"), url("/vacation"), url("/pics/b.png")],
            isDirectory: { $0.lastPathComponent == "vacation" }
        )
        XCTAssertEqual(decision, .folder(url("/vacation")))
    }

    func testOneImageOpensThatFile() {
        let decision = DropRouting.decide(urls: [url("/pics/a.jpg")], isDirectory: { _ in false })
        XCTAssertEqual(decision, .image(url("/pics/a.jpg")))
    }

    func testSeveralImagesFromOneFolderStayTogether() {
        let decision = DropRouting.decide(
            urls: [url("/pics/b.jpg"), url("/pics/a.png")],
            isDirectory: { _ in false }
        )
        XCTAssertEqual(decision, .images(folder: url("/pics"), files: [url("/pics/b.jpg"), url("/pics/a.png")]))
    }

    func testImagesFromDifferentFoldersOpenTheFirst() {
        let decision = DropRouting.decide(
            urls: [url("/one/a.jpg"), url("/two/b.jpg")],
            isDirectory: { _ in false }
        )
        XCTAssertEqual(decision, .image(url("/one/a.jpg")))
    }

    func testUnknownFilesAreIgnored() {
        XCTAssertNil(DropRouting.decide(urls: [url("/pics/notes.txt")], isDirectory: { _ in false }))
        XCTAssertNil(DropRouting.decide(urls: [], isDirectory: { _ in false }))
    }
}
