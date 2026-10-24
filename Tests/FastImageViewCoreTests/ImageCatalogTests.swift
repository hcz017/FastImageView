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

    func testRefreshKeepsFilterAndMovesSelectionAfterDeletion() {
        var catalog = ImageCatalog()
        let a = file("a.jpg", format: .jpeg)
        let b = file("b.jpg", format: .jpeg)
        let c = file("c.nef", format: .nef)
        catalog.files = [a, b, c]
        catalog.keyword = "jpg"
        catalog.selectionID = a.url
        catalog.refresh(with: [b, c])
        XCTAssertEqual(catalog.keyword, "jpg")
        XCTAssertEqual(catalog.filtered.map(\.filename), ["b.jpg"])
        XCTAssertEqual(catalog.selectionID, b.url)
    }

    func testRefreshFollowsRenamedSelection() {
        var catalog = ImageCatalog()
        let a = file("a.jpg", format: .jpeg)
        let renamed = file("a-renamed.jpg", format: .jpeg)
        catalog.files = [a]
        catalog.selectionID = a.url
        catalog.refresh(with: [renamed], renamedSelection: renamed.url)
        XCTAssertEqual(catalog.selectionID, renamed.url)
    }

    func testRemoveSelectsNextOrPrevious() {
        var catalog = ImageCatalog()
        catalog.files = [file("a.jpg", format: .jpeg), file("b.jpg", format: .jpeg), file("c.jpg", format: .jpeg)]
        catalog.applySelection(url: catalog.files[0].url, gesture: .only)
        _ = catalog.removeSelected()
        XCTAssertEqual(catalog.selectedFile?.filename, "b.jpg")
        catalog.applySelection(url: catalog.files[catalog.files.count - 1].url, gesture: .only)
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

    func testClickToggleAndShiftSelectARange() {
        var catalog = ImageCatalog()
        catalog.files = [
            file("a.jpg", format: .jpeg),
            file("b.jpg", format: .jpeg),
            file("c.jpg", format: .jpeg),
            file("d.jpg", format: .jpeg)
        ]
        catalog.applySelection(url: catalog.files[0].url, gesture: .only)
        catalog.applySelection(url: catalog.files[2].url, gesture: .extend)
        XCTAssertEqual(catalog.deletionTargets.map(\.filename), ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertEqual(catalog.selectionID, catalog.files[2].url)

        catalog.applySelection(url: catalog.files[1].url, gesture: .toggle)
        XCTAssertEqual(catalog.deletionTargets.map(\.filename), ["a.jpg", "c.jpg"])
        XCTAssertEqual(catalog.selectionID, catalog.files[2].url)

        catalog.applySelection(url: catalog.files[3].url, gesture: .only)
        XCTAssertEqual(catalog.deletionTargets.map(\.filename), ["d.jpg"])
    }

    func testRemovingARangeSelectsTheFollowingItemAndUndoRestoresTheSet() {
        var catalog = ImageCatalog()
        catalog.files = [
            file("a.jpg", format: .jpeg),
            file("b.jpg", format: .jpeg),
            file("c.jpg", format: .jpeg),
            file("d.jpg", format: .jpeg)
        ]
        catalog.applySelection(url: catalog.files[1].url, gesture: .only)
        catalog.applySelection(url: catalog.files[2].url, gesture: .extend)
        let removed = catalog.removeSelected()
        XCTAssertEqual(removed.map(\.filename), ["b.jpg", "c.jpg"])
        XCTAssertEqual(catalog.selectedFile?.filename, "d.jpg")
        catalog.restore(removed)
        XCTAssertEqual(catalog.deletionTargets.map(\.filename), ["b.jpg", "c.jpg"])
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

    func testRatingFilterORsLevelsWithUnratedAndANDsOtherFilters() {
        var catalog = ImageCatalog()
        let a = file("a.jpg", format: .jpeg)
        let b = file("b.jpg", format: .jpeg)
        let c = file("c.png", format: .png)
        catalog.files = [a, b, c]
        catalog.ratings = [a.url: 3, b.url: 5]
        catalog.selectionID = c.url

        catalog.selectedRatings = [3]
        XCTAssertEqual(catalog.filtered.map(\.filename), ["a.jpg"])
        catalog.selectedRatings = [3, 5]
        XCTAssertEqual(catalog.filtered.map(\.filename), ["a.jpg", "b.jpg"])

        catalog.selectedRatings = []
        catalog.includesUnrated = true
        XCTAssertEqual(catalog.filtered.map(\.filename), ["c.png"])
        XCTAssertTrue(catalog.hasRatingFilter)

        catalog.includesUnrated = false
        catalog.selectedRatings = [5]
        catalog.selectedFormats = [.png]
        XCTAssertTrue(catalog.filtered.isEmpty)
        catalog.clampSelection()
        XCTAssertNil(catalog.selectionID)
    }

    func testReplaceFilesClearsRatingFilter() {
        var catalog = ImageCatalog()
        catalog.files = [file("a.jpg", format: .jpeg)]
        catalog.selectedRatings = [3]
        catalog.includesUnrated = true
        catalog.replaceFiles([file("b.jpg", format: .jpeg)])
        XCTAssertTrue(catalog.selectedRatings.isEmpty)
        XCTAssertFalse(catalog.includesUnrated)
    }
}
