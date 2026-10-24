import XCTest
@testable import FastImageViewCore

final class KeyRoutingTests: XCTestCase {
    private func key(_ code: UInt16, command: Bool = false, shift: Bool = false, chars: String = "") -> KeyChord {
        KeyChord(keyCode: code, command: command, shift: shift, charactersIgnoringModifiers: chars)
    }

    func testKeywordFieldOwnsDeleteAndUndo() {
        XCTAssertEqual(interpretKey(key(51), focus: .keyword, mode: .grid), .passThrough)
        XCTAssertEqual(interpretKey(key(6, command: true, chars: "z"), focus: .keyword, mode: .grid), .passThrough)
        XCTAssertEqual(interpretKey(key(53), focus: .keyword, mode: .grid), .resignKeywordFocus)
        XCTAssertEqual(interpretKey(key(36), focus: .keyword, mode: .grid), .resignKeywordFocus)
    }

    func testBrowserDeleteUndoAndArrows() {
        XCTAssertEqual(interpretKey(key(51), focus: .browser, mode: .grid), .deletePhoto)
        XCTAssertEqual(interpretKey(key(117), focus: .browser, mode: .viewer), .deletePhoto)
        XCTAssertEqual(interpretKey(key(51, command: true), focus: .browser, mode: .grid), .deletePhoto)
        XCTAssertEqual(interpretKey(key(6, command: true, chars: "z"), focus: .browser, mode: .grid), .undoTrash)
        XCTAssertEqual(interpretKey(key(124), focus: .browser, mode: .grid), .move(1))
        XCTAssertEqual(interpretKey(key(123), focus: .browser, mode: .viewer), .move(-1))
        XCTAssertEqual(interpretKey(key(125), focus: .browser, mode: .grid), .moveRow(1))
        XCTAssertEqual(interpretKey(key(126), focus: .browser, mode: .grid), .moveRow(-1))
        XCTAssertEqual(interpretKey(key(125), focus: .browser, mode: .viewer), .move(1))
        XCTAssertEqual(interpretKey(key(126), focus: .browser, mode: .viewer), .move(-1))
    }

    func testViewerFitAndEscapeDoNotApplyInGrid() {
        XCTAssertEqual(interpretKey(key(18), focus: .browser, mode: .viewer), .setRating(1))
        XCTAssertEqual(interpretKey(key(29), focus: .browser, mode: .viewer), .passThrough)
        XCTAssertEqual(interpretKey(key(18), focus: .browser, mode: .grid), .setRating(1))
        XCTAssertEqual(interpretKey(key(34, chars: "i"), focus: .browser, mode: .viewer), .toggleCaptureInfo)
        XCTAssertEqual(interpretKey(key(34, chars: "i"), focus: .browser, mode: .grid), .passThrough)
        XCTAssertEqual(interpretKey(key(34, chars: "i"), focus: .keyword, mode: .viewer), .passThrough)
        XCTAssertEqual(interpretKey(key(53), focus: .browser, mode: .viewer), .closeViewer)
        XCTAssertEqual(interpretKey(key(36), focus: .browser, mode: .grid), .openViewer)
        XCTAssertEqual(interpretKey(key(31, command: true, chars: "o"), focus: .keyword, mode: .grid), .openFolder)
    }

    func testViewerZoomAndCopyStayOutOfTheSearchField() {
        XCTAssertEqual(interpretKey(key(24, command: true, chars: "="), focus: .browser, mode: .viewer), .zoomIn)
        XCTAssertEqual(interpretKey(key(27, command: true, chars: "-"), focus: .browser, mode: .viewer), .zoomOut)
        XCTAssertEqual(interpretKey(key(8, command: true, chars: "c"), focus: .browser, mode: .grid), .copyImage)
        XCTAssertEqual(interpretKey(key(24, command: true, chars: "="), focus: .browser, mode: .grid), .passThrough)
        XCTAssertEqual(interpretKey(key(8, command: true, chars: "c"), focus: .keyword, mode: .grid), .passThrough)
        XCTAssertEqual(interpretKey(key(27, command: true, chars: "-"), focus: .keyword, mode: .viewer), .passThrough)
        XCTAssertEqual(interpretKey(key(3, command: true, chars: "f"), focus: .browser, mode: .grid), .focusSearch)
        XCTAssertEqual(interpretKey(key(3, command: true, chars: "f"), focus: .browser, mode: .viewer), .focusSearch)
        XCTAssertEqual(interpretKey(key(3, command: true, chars: "f"), focus: .keyword, mode: .grid), .passThrough)
        XCTAssertEqual(interpretKey(key(3, command: true, chars: "f"), focus: .browser, mode: .noFolder), .passThrough)
    }

    func testSpaceActsLikeQuickLook() {
        XCTAssertEqual(interpretKey(key(49), focus: .browser, mode: .grid), .openViewer)
        XCTAssertEqual(interpretKey(key(49), focus: .browser, mode: .viewer), .closeViewer)
        XCTAssertEqual(interpretKey(key(49), focus: .keyword, mode: .grid), .passThrough)
        XCTAssertEqual(interpretKey(key(49, command: true), focus: .browser, mode: .grid), .passThrough)
    }

    func testNumberKeysRateInGridAndViewerAndShiftFiltersOnlyInGrid() {
        let levels: [(UInt16, Int)] = [(18, 1), (19, 2), (20, 3), (21, 4), (23, 5)]
        for (code, level) in levels {
            XCTAssertEqual(interpretKey(key(code), focus: .browser, mode: .grid), .setRating(level))
            XCTAssertEqual(interpretKey(key(code), focus: .browser, mode: .viewer), .setRating(level))
            XCTAssertEqual(interpretKey(key(code, shift: true), focus: .browser, mode: .grid), .toggleRatingFilter(level))
            XCTAssertEqual(interpretKey(key(code, shift: true), focus: .browser, mode: .viewer), .passThrough)
        }
        XCTAssertEqual(interpretKey(key(18), focus: .keyword, mode: .grid), .passThrough)
        XCTAssertEqual(interpretKey(key(18, shift: true), focus: .keyword, mode: .grid), .passThrough)
        XCTAssertEqual(interpretKey(key(18, command: true), focus: .browser, mode: .grid), .passThrough)
        XCTAssertEqual(interpretKey(key(18), focus: .browser, mode: .noFolder), .passThrough)
    }

    func testPEntersCompareOnlyFromGridWithoutSearchFocus() {
        XCTAssertEqual(interpretKey(key(35, chars: "p"), focus: .browser, mode: .grid), .openCompare)
        XCTAssertEqual(interpretKey(key(35, chars: "p"), focus: .keyword, mode: .grid), .passThrough)
        XCTAssertEqual(interpretKey(key(35, chars: "p"), focus: .browser, mode: .viewer), .passThrough)
        XCTAssertEqual(interpretKey(key(35, chars: "p"), focus: .browser, mode: .noFolder), .passThrough)
        XCTAssertEqual(interpretKey(key(35, command: true, chars: "p"), focus: .browser, mode: .grid), .passThrough)
    }

    func testCompareModeEscapeSpaceAndZoom() {
        XCTAssertEqual(interpretKey(key(53), focus: .browser, mode: .compare), .closeViewer)
        XCTAssertEqual(interpretKey(key(49), focus: .browser, mode: .compare), .closeViewer)
        XCTAssertEqual(interpretKey(key(24, command: true, chars: "="), focus: .browser, mode: .compare), .zoomIn)
        XCTAssertEqual(interpretKey(key(27, command: true, chars: "-"), focus: .browser, mode: .compare), .zoomOut)
        XCTAssertEqual(interpretKey(key(8, command: true, chars: "c"), focus: .browser, mode: .compare), .copyImage)
        XCTAssertEqual(interpretKey(key(6, command: true, chars: "z"), focus: .browser, mode: .compare), .undoTrash)
    }

    func testCompareModeConsumesDestructiveAndNavigationKeys() {
        for code: UInt16 in [51, 117, 123, 124, 125, 126, 36, 35, 18, 19, 20, 21, 23] {
            XCTAssertEqual(interpretKey(key(code), focus: .browser, mode: .compare), .consume, "keyCode \(code)")
        }
        XCTAssertEqual(interpretKey(key(18, shift: true), focus: .browser, mode: .compare), .consume)
        XCTAssertEqual(interpretKey(key(51, command: true), focus: .browser, mode: .compare), .consume)
    }
}
