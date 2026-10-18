import XCTest
@testable import FastImageViewCore

final class GridLayoutTests: XCTestCase {
    func testColumnCountFollowsAdaptiveTiles() {
        XCTAssertEqual(
            GridLayout.columnCount(availableWidth: 688, minimum: 168, maximum: 220, spacing: 12),
            3
        )
        XCTAssertEqual(
            GridLayout.columnCount(availableWidth: 1400, minimum: 168, maximum: 220, spacing: 12),
            7
        )
        XCTAssertEqual(GridLayout.columnCount(availableWidth: 40, minimum: 168, maximum: 220, spacing: 12), 1)
    }

    func testVerticalMoveStepsByARowAndStopsAtTheEnds() {
        XCTAssertEqual(GridLayout.rowIndex(from: 0, count: 10, columns: 4, deltaRows: 1), 4)
        XCTAssertEqual(GridLayout.rowIndex(from: 5, count: 10, columns: 4, deltaRows: -1), 1)
        XCTAssertEqual(GridLayout.rowIndex(from: 6, count: 10, columns: 4, deltaRows: 1), 9)
        XCTAssertEqual(GridLayout.rowIndex(from: 8, count: 10, columns: 4, deltaRows: 1), 8)
        XCTAssertEqual(GridLayout.rowIndex(from: 1, count: 10, columns: 4, deltaRows: -1), 1)
    }
}
