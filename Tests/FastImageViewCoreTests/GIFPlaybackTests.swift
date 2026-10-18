import XCTest
@testable import FastImageViewCore

final class GIFPlaybackTests: XCTestCase {
    func testShortDelaysBecomeATenthOfASecond() {
        XCTAssertEqual(GIFPlayback.delay(unclamped: 0, fallback: 0.5), 0.1)
        XCTAssertEqual(GIFPlayback.delay(unclamped: nil, fallback: nil), 0.1)
        XCTAssertEqual(GIFPlayback.delay(unclamped: nil, fallback: 0.05), 0.05)
        XCTAssertEqual(GIFPlayback.delay(unclamped: 0.2, fallback: 0.05), 0.2)
    }

    func testFrameIndexLoopsAcrossTheDelays() {
        let delays = [0.1, 0.1, 0.2]
        XCTAssertEqual(GIFPlayback.index(elapsed: 0, delays: delays), 0)
        XCTAssertEqual(GIFPlayback.index(elapsed: 0.1, delays: delays), 1)
        XCTAssertEqual(GIFPlayback.index(elapsed: 0.25, delays: delays), 2)
        XCTAssertEqual(GIFPlayback.index(elapsed: 0.4, delays: delays), 0)
        XCTAssertEqual(GIFPlayback.index(elapsed: 0, delays: []), 0)
    }
}
