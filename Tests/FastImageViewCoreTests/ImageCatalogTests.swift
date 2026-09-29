import XCTest
@testable import FastImageViewCore

final class ImageCatalogTests: XCTestCase {
    private func file(_ name: String, format: ImageFormat) -> ImageFile {
        ImageFile(url: URL(fileURLWithPath: "/tmp/\(name)"), filename: name, format: format, modificationDate: .distantPast, iCloudState: .notCloud)
    }

    func testKeywordMatchesFullFilenameAndIntersectsFormat() {
        var catalog = ImageCatalog()
        catalog.files = [file("IMG_1.jpg", format: .jpeg), file("IMG_2.NEF", format: .nef), file("cat.png", format: .png)]
        catalog.selectionID = catalog.files[0].url
        catalog.keyword = "jpg"
        catalog.clampSelection()
        XCTAssertEqual(catalog.filtered.map(\.filename), ["IMG_1.jpg"])
        catalog.keyword = "img"
        catalog.selectedFormats = [.nef]
        catalog.clampSelection()
        XCTAssertEqual(catalog.filtered.map(\.filename), ["IMG_2.NEF"])
        XCTAssertEqual(catalog.selectionID, catalog.files[1].url)
    }

    func testEmptyFormatSelectionMeansAllAndEmptyResultClearsSelection() {
        var catalog = ImageCatalog()
        catalog.files = [file("a.jpg", format: .jpeg)]
        catalog.selectionID = catalog.files[0].url
        catalog.selectedFormats = []
        catalog.clampSelection()
        XCTAssertEqual(catalog.filtered.count, 1)
        catalog.keyword = "missing"
        catalog.clampSelection()
        XCTAssertTrue(catalog.filtered.isEmpty)
        XCTAssertNil(catalog.selectionID)
    }

    func testRemoveSelectsNextOrPrevious() {
        var catalog = ImageCatalog()
        catalog.files = [file("a.jpg", format: .jpeg), file("b.jpg", format: .jpeg), file("c.jpg", format: .jpeg)]
        catalog.selectionID = catalog.files[0].url
        _ = catalog.removeSelected()
        XCTAssertEqual(catalog.selectedFile?.filename, "b.jpg")
        catalog.selectionID = catalog.files.last?.url
        _ = catalog.removeSelected()
        XCTAssertEqual(catalog.selectedFile?.filename, "b.jpg")
        _ = catalog.removeSelected()
        XCTAssertNil(catalog.selectionID)
    }

    func testRestoreSelectsFileWhenItMatchesFilter() {
        var catalog = ImageCatalog()
        let jpg = file("a.jpg", format: .jpeg)
        let nef = file("b.nef", format: .nef)
        catalog.files = [jpg]
        catalog.selectionID = jpg.url
        catalog.selectedFormats = [.jpeg, .nef]
        catalog.restore(nef)
        XCTAssertEqual(catalog.files.map(\.filename), ["a.jpg", "b.nef"])
        XCTAssertEqual(catalog.selectionID, nef.url)
    }

    func testRestoreKeepsSelectionWhenFileIsFilteredOut() {
        var catalog = ImageCatalog()
        let jpg = file("a.jpg", format: .jpeg)
        let nef = file("b.nef", format: .nef)
        catalog.files = [jpg]
        catalog.selectionID = jpg.url
        catalog.selectedFormats = [.jpeg]
        catalog.restore(nef)
        XCTAssertEqual(catalog.selectionID, jpg.url)
        XCTAssertEqual(catalog.files.map(\.filename), ["a.jpg", "b.nef"])
    }

    func testMoveDoesNotWrap() {
        var catalog = ImageCatalog()
        catalog.files = [file("a.jpg", format: .jpeg), file("b.jpg", format: .jpeg)]
        catalog.selectionID = catalog.files[0].url
        catalog.moveSelection(by: -1)
        XCTAssertEqual(catalog.selectionID, catalog.files[0].url)
        catalog.moveSelection(by: 1)
        catalog.moveSelection(by: 1)
        XCTAssertEqual(catalog.selectionID, catalog.files[1].url)
    }
}
