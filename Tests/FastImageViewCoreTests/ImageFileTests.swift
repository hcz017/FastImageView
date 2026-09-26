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

    func testICloudMapping() {
        XCTAssertEqual(ICloudState.map(isUbiquitous: false, status: .notDownloaded), .notCloud)
        XCTAssertEqual(ICloudState.map(isUbiquitous: true, status: .notDownloaded), .notDownloaded)
        XCTAssertEqual(ICloudState.map(isUbiquitous: true, status: .downloaded), .downloaded)
        XCTAssertEqual(ICloudState.map(isUbiquitous: true, status: .current), .downloaded)
        XCTAssertEqual(ICloudState.map(isUbiquitous: true, status: nil), .downloaded)
    }
}
