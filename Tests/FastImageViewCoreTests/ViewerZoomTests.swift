import XCTest
@testable import FastImageViewCore

final class ViewerZoomTests: XCTestCase {
    func testClampAndStepStayInsideTheRange() {
        XCTAssertEqual(ZoomMath.clamp(0.01), ZoomMath.minimum)
        XCTAssertEqual(ZoomMath.clamp(20), ZoomMath.maximum)
        XCTAssertEqual(ZoomMath.stepped(1, direction: 1), 1.25)
        XCTAssertEqual(ZoomMath.stepped(1, direction: -1), 1 / ZoomMath.step, accuracy: 0.000_001)
        XCTAssertEqual(ZoomMath.stepped(ZoomMath.maximum, direction: 1), ZoomMath.maximum)
    }

    func testMagnifyAndScrollMultiplyTheCurrentLevel() {
        XCTAssertEqual(ZoomMath.applyingMagnify(multiple: 1, magnification: 0.5), 1.5)
        XCTAssertEqual(ZoomMath.applyingMagnify(multiple: 2, magnification: -0.5), 1)
        let zoomed = ZoomMath.applyingScroll(multiple: 1, deltaY: 100)
        XCTAssertGreaterThan(zoomed, 1)
        let reduced = ZoomMath.applyingScroll(multiple: 2, deltaY: -100)
        XCTAssertLessThan(reduced, 2)
    }

    func testActualPixelsIsTheInverseOfTheFitScale() {
        XCTAssertEqual(ZoomMath.fitScale(imageWidth: 200, imageHeight: 100, viewportWidth: 100, viewportHeight: 100), 0.5)
        XCTAssertEqual(ZoomMath.actualMultiple(fitScale: 0.5), 2)
        XCTAssertEqual(ZoomMath.displayScale(fitScale: 0.5, multiple: 2), 1)
    }

    func testNearFitSnapsBackToFit() {
        XCTAssertTrue(ZoomMath.isFit(1))
        XCTAssertTrue(ZoomMath.isFit(1.01))
        XCTAssertFalse(ZoomMath.isFit(1.25))
    }

    func testPanStopsAtTheImageEdge() {
        let pan = ImagePan.clamped(
            x: 500,
            y: -80,
            contentWidth: 400,
            contentHeight: 200,
            viewportWidth: 300,
            viewportHeight: 200
        )
        XCTAssertEqual(pan.x, 50)
        XCTAssertEqual(pan.y, 0)
    }

    func testPanIsAvailableOnlyWhenTheImageOverflows() {
        XCTAssertFalse(ZoomMath.prefersPan(contentWidth: 100, contentHeight: 80, viewportWidth: 300, viewportHeight: 200))
        XCTAssertTrue(ZoomMath.prefersPan(contentWidth: 400, contentHeight: 80, viewportWidth: 300, viewportHeight: 200))
    }

    func testDecodeSizeGrowsOnceTheViewLeavesFit() {
        XCTAssertEqual(PreviewMaxPixel.viewer(zoom: .fit, screenLongEdge: 1800), 1800)
        XCTAssertEqual(PreviewMaxPixel.viewer(zoom: .actual, screenLongEdge: 1800), 16384)
        XCTAssertEqual(PreviewMaxPixel.viewer(zoom: .multiple(1.5), screenLongEdge: 1800), 16384)
    }
}
