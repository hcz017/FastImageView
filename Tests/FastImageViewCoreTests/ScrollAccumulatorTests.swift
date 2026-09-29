import XCTest
@testable import FastImageViewCore

final class ScrollAccumulatorTests: XCTestCase {
    func testPreciseScrollSwitchesAt80AndClearsBothAxes() {
        var acc = ScrollAccumulator()
        let first = acc.consume(ScrollSample(deltaX: 30, deltaY: 40, precise: true, fingerDown: true, inertial: false))
        XCTAssertEqual(first, 0)
        let second = acc.consume(ScrollSample(deltaX: 10, deltaY: 50, precise: true, fingerDown: true, inertial: false))
        XCTAssertEqual(second, 1)
        let third = acc.consume(ScrollSample(deltaX: 79, deltaY: 0, precise: true, fingerDown: true, inertial: false))
        XCTAssertEqual(third, 0)
    }

    func testInertiaDoesNotSwitch() {
        var acc = ScrollAccumulator()
        let step = acc.consume(ScrollSample(deltaX: 0, deltaY: 200, precise: true, fingerDown: false, inertial: true))
        XCTAssertEqual(step, 0)
    }

    func testMouseNotchSwitchesOnceByDominantAxis() {
        var acc = ScrollAccumulator()
        XCTAssertEqual(acc.consume(ScrollSample(deltaX: 0, deltaY: 1, precise: false, fingerDown: false, inertial: false)), 1)
        XCTAssertEqual(acc.consume(ScrollSample(deltaX: -3, deltaY: 1, precise: false, fingerDown: false, inertial: false)), -1)
    }

    func testSpecDeltasFlipVerticalAxis() {
        let deltas = specDeltas(scrollingDeltaX: 5, scrollingDeltaY: 8)
        XCTAssertEqual(deltas.x, 5)
        XCTAssertEqual(deltas.y, -8)
    }
}
