import XCTest
@testable import FastImageViewCore

final class CopyRoutingTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/pics/\(name)") }

    func testSingleFileCopiesItsOwnImageAndPath() {
        let set = CopyRouting.make(clicked: url("a.jpg"), orderedSelection: [url("a.jpg")])
        XCTAssertEqual(set.imageURL, url("a.jpg"))
        XCTAssertEqual(set.paths, ["/pics/a.jpg"])
    }

    func testClickedMemberOfAMultiSelectionCopiesEveryPath() {
        let set = CopyRouting.make(
            clicked: url("b.jpg"),
            orderedSelection: [url("a.jpg"), url("b.jpg"), url("c.jpg")]
        )
        XCTAssertEqual(set.imageURL, url("b.jpg"))
        XCTAssertEqual(set.paths, ["/pics/a.jpg", "/pics/b.jpg", "/pics/c.jpg"])
    }

    func testClickOutsideTheSelectionCopiesOnlyThatFile() {
        let set = CopyRouting.make(clicked: url("z.jpg"), orderedSelection: [url("a.jpg"), url("b.jpg")])
        XCTAssertEqual(set.imageURL, url("z.jpg"))
        XCTAssertEqual(set.paths, ["/pics/z.jpg"])
    }
}
