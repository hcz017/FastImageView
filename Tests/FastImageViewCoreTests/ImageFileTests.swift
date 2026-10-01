import XCTest
@testable import FastImageViewCore

final class ImageFileTests: XCTestCase {
    func testRecognizesExtensionsWithoutCase() {
        XCTAssertEqual(ImageFormat.from(filename: "A.JPG"), .jpeg)
        XCTAssertEqual(ImageFormat.from(filename: "a.jpeg"), .jpeg)
        XCTAssertEqual(ImageFormat.from(filename: "a.heif"), .heic)
        XCTAssertEqual(ImageFormat.from(filename: "a.tif"), .tiff)
        XCTAssertEqual(ImageFormat.from(filename: "shot.NEF"), .nef)
        XCTAssertEqual(ImageFormat.from(filename: "a.CR3"), .cr3)
        XCTAssertNil(ImageFormat.from(filename: "notes.txt"))
        XCTAssertNil(ImageFormat.from(filename: "archive"))
    }

    func testBadgeUsesShortNamesAndMarksRaw() {
        XCTAssertEqual(ImageFormat.jpeg.badge, "JPG")
        XCTAssertEqual(ImageFormat.tiff.badge, "TIF")
        XCTAssertEqual(ImageFormat.heic.badge, "HEIC")
        XCTAssertEqual(ImageFormat.nef.badge, "NEF")
        XCTAssertTrue(ImageFormat.cr3.isRaw)
        XCTAssertFalse(ImageFormat.png.isRaw)
    }

    func testICloudMapping() {
        XCTAssertEqual(ICloudState.map(isUbiquitous: false, status: .notDownloaded), .notCloud)
        XCTAssertEqual(ICloudState.map(isUbiquitous: true, status: .notDownloaded), .notDownloaded)
        XCTAssertEqual(ICloudState.map(isUbiquitous: true, status: .downloaded), .downloaded)
        XCTAssertEqual(ICloudState.map(isUbiquitous: true, status: .current), .downloaded)
        XCTAssertEqual(ICloudState.map(isUbiquitous: true, status: nil), .downloaded)
    }
}
