import XCTest
@testable import FastImageViewCore

final class KeyRoutingTests: XCTestCase {
    private func key(_ code: UInt16, command: Bool = false, chars: String = "") -> KeyChord {
        KeyChord(keyCode: code, command: command, charactersIgnoringModifiers: chars)
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
        XCTAssertEqual(interpretKey(key(125), focus: .browser, mode: .grid), .move(1))
        XCTAssertEqual(interpretKey(key(126), focus: .browser, mode: .grid), .move(-1))
    }

    func testViewerFitAndEscapeDoNotApplyInGrid() {
        XCTAssertEqual(interpretKey(key(18), focus: .browser, mode: .viewer), .actualPixels)
        XCTAssertEqual(interpretKey(key(29), focus: .browser, mode: .viewer), .fit)
        XCTAssertEqual(interpretKey(key(18), focus: .browser, mode: .grid), .passThrough)
        XCTAssertEqual(interpretKey(key(53), focus: .browser, mode: .viewer), .closeViewer)
        XCTAssertEqual(interpretKey(key(36), focus: .browser, mode: .grid), .openViewer)
        XCTAssertEqual(interpretKey(key(31, command: true, chars: "o"), focus: .keyword, mode: .grid), .openFolder)
    }
}
