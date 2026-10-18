import ImageIO
import XCTest
@testable import FastImageViewCore

final class CaptureInfoTests: XCTestCase {
    func testFormatsTheShootingFields() {
        XCTAssertEqual(CaptureInfoFormatter.date("2026:10:18 15:04:02"), "2026-10-18 15:04")
        XCTAssertEqual(CaptureInfoFormatter.camera(make: "Apple", model: "iPhone 15 Pro"), "Apple iPhone 15 Pro")
        XCTAssertEqual(CaptureInfoFormatter.camera(make: "Apple", model: "Apple iPhone 15 Pro"), "Apple iPhone 15 Pro")
        XCTAssertEqual(CaptureInfoFormatter.camera(make: "NIKON CORPORATION", model: "NIKON Z 8"), "NIKON CORPORATION NIKON Z 8")
        XCTAssertNil(CaptureInfoFormatter.lens("iPhone 15 Pro", camera: "iPhone 15 Pro"))
        XCTAssertEqual(CaptureInfoFormatter.aperture(1.8), "f/1.8")
        XCTAssertEqual(CaptureInfoFormatter.aperture(8), "f/8")
        XCTAssertEqual(CaptureInfoFormatter.shutter(1.0 / 120.0), "1/120")
        XCTAssertEqual(CaptureInfoFormatter.shutter(2), "2s")
        XCTAssertEqual(CaptureInfoFormatter.iso(100), "ISO 100")
        XCTAssertEqual(CaptureInfoFormatter.focalLength(24), "24mm")
        XCTAssertEqual(CaptureInfoFormatter.pixelSize(width: 4032, height: 3024), "4032×3024")
    }

    func testSummaryJoinsWhateverWasRecorded() {
        let exif: [CFString: Any] = [
            kCGImagePropertyExifDateTimeOriginal: "2026:10:18 15:04:02",
            kCGImagePropertyExifFNumber: 1.8,
            kCGImagePropertyExifExposureTime: 1.0 / 125.0,
            kCGImagePropertyExifISOSpeedRatings: [80],
            kCGImagePropertyExifFocalLength: 6.9,
            kCGImagePropertyExifLensModel: "iPhone 15 Pro back camera"
        ]
        let tiff: [CFString: Any] = [
            kCGImagePropertyTIFFMake: "Apple",
            kCGImagePropertyTIFFModel: "iPhone 15 Pro"
        ]
        let info = CaptureInfoReader.parse([
            kCGImagePropertyPixelWidth: 4032,
            kCGImagePropertyPixelHeight: 3024,
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyTIFFDictionary: tiff
        ])
        XCTAssertEqual(
            info.lines,
            [
                "2026-10-18 15:04",
                "Apple iPhone 15 Pro · iPhone 15 Pro back camera",
                "f/1.8 · 1/125 · ISO 80 · 6.9mm · 4032×3024"
            ]
        )
        XCTAssertEqual(
            info.summary,
            """
            2026-10-18 15:04
            Apple iPhone 15 Pro · iPhone 15 Pro back camera
            f/1.8 · 1/125 · ISO 80 · 6.9mm · 4032×3024
            """
        )
    }

    func testDimensionsAloneAreStillShown() {
        let info = CaptureInfoReader.parse([
            kCGImagePropertyPixelWidth: 800,
            kCGImagePropertyPixelHeight: 600
        ])
        XCTAssertEqual(info.lines, ["800×600"])
        XCTAssertEqual(info.summary, "800×600")
    }
}
