import XCTest
@testable import FastImageViewCore

final class CompareModeTests: XCTestCase {
    private func file(_ name: String, format: ImageFormat = .jpeg) -> ImageFile {
        ImageFile(
            url: URL(fileURLWithPath: "/pics/\(name)"),
            filename: name,
            format: format,
            modificationDate: .distantPast,
            iCloudState: .notCloud
        )
    }

    private func catalog(files: [ImageFile], selection: [URL]) -> ImageCatalog {
        var catalog = ImageCatalog()
        catalog.replaceFiles(files)
        catalog.applySelection(url: selection[0], gesture: .only)
        for url in selection.dropFirst() {
            catalog.applySelection(url: url, gesture: .toggle)
        }
        return catalog
    }

    private func layout(content: Double, viewport: Double) -> ViewerLayout {
        ViewerLayout(
            contentWidth: content,
            contentHeight: content,
            viewportWidth: viewport,
            viewportHeight: viewport,
            fitScale: 1
        )
    }

    func testCompareSelectionFollowsDisplayOrderAndLimit() {
        let files = [file("a.jpg"), file("b.jpg"), file("c.jpg"), file("d.jpg")]
        let catalog = catalog(files: files, selection: [files[3].url, files[0].url, files[2].url])
        XCTAssertEqual(catalog.compareSelection().map(\.filename), ["a.jpg", "c.jpg", "d.jpg"])
        XCTAssertEqual(catalog.compareSelection(limit: 2).map(\.filename), ["a.jpg", "c.jpg"])
    }

    func testCompareSelectionIgnoresHiddenAndEmptySelection() {
        let files = [file("a.jpg"), file("b.nef", format: .nef)]
        var filtered = catalog(files: files, selection: files.map(\.url))
        filtered.selectedFormats = [.nef]
        filtered.clampSelection()
        XCTAssertEqual(filtered.compareSelection().map(\.filename), ["b.nef"])

        var empty = ImageCatalog()
        empty.replaceFiles(files)
        empty.selectionID = nil
        empty.selectionIDs = []
        XCTAssertTrue(empty.compareSelection().isEmpty)
    }

    func testFocusMovesOnlyCurrentSelection() {
        let files = [file("a.jpg"), file("b.jpg"), file("c.jpg")]
        var catalog = catalog(files: files, selection: files.map(\.url))
        catalog.focus(url: files[1].url)
        XCTAssertEqual(catalog.selectionID, files[1].url)
        XCTAssertEqual(catalog.selectionIDs, Set(files.map(\.url)))
        XCTAssertEqual(catalog.selectionAnchor, files[0].url)
    }

    func testClampedUsesTwoPaneIntersection() {
        let narrow = layout(content: 2400, viewport: 1000)
        let wide = layout(content: 3000, viewport: 1000)
        let pan = ComparePan.clamped(x: 900, y: -900, layouts: [narrow, wide])
        XCTAssertEqual(pan.x, 700)
        XCTAssertEqual(pan.y, -700)
    }

    func testClampedLocksAxisWhenAnyPaneFits() {
        let zoomed = ViewerLayout(contentWidth: 2400, contentHeight: 1200, viewportWidth: 1000, viewportHeight: 1000, fitScale: 1)
        let fitting = ViewerLayout(contentWidth: 800, contentHeight: 500, viewportWidth: 1000, viewportHeight: 1000, fitScale: 1)
        let pan = ComparePan.clamped(x: 500, y: 500, layouts: [zoomed, fitting])
        XCTAssertEqual(pan.x, 0)
        XCTAssertEqual(pan.y, 0)
    }

    func testClampedWithoutLayoutsIsZero() {
        XCTAssertEqual(ComparePan.clamped(x: 100, y: -100, layouts: []), .zero)
    }
}
