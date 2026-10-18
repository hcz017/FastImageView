import Foundation
import ImageIO

public struct CaptureInfo: Equatable, Sendable {
    public var capturedAt: String?
    public var camera: String?
    public var lens: String?
    public var aperture: String?
    public var shutter: String?
    public var iso: String?
    public var focalLength: String?
    public var pixelSize: String?

    public init(
        capturedAt: String? = nil,
        camera: String? = nil,
        lens: String? = nil,
        aperture: String? = nil,
        shutter: String? = nil,
        iso: String? = nil,
        focalLength: String? = nil,
        pixelSize: String? = nil
    ) {
        self.capturedAt = capturedAt
        self.camera = camera
        self.lens = lens
        self.aperture = aperture
        self.shutter = shutter
        self.iso = iso
        self.focalLength = focalLength
        self.pixelSize = pixelSize
    }

    public var lines: [String] {
        var rows: [String] = []
        appendLabeled(&rows, name: "拍摄时间", value: capturedAt)
        appendLabeled(&rows, name: "相机", value: camera)
        appendLabeled(&rows, name: "镜头", value: lens)
        appendLabeled(&rows, name: "光圈", value: aperture)
        appendLabeled(&rows, name: "快门", value: shutter)
        appendLabeled(&rows, name: "ISO", value: iso)
        appendLabeled(&rows, name: "焦距", value: focalLength)
        appendLabeled(&rows, name: "尺寸", value: pixelSize)
        return rows
    }

    private func appendLabeled(_ rows: inout [String], name: String, value: String?) {
        guard let value, !value.isEmpty else { return }
        rows.append("\(name)：\(value)")
    }

    public var summary: String {
        lines.joined(separator: "\n")
    }
}

public enum CaptureInfoFormatter {
    public static func date(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let pieces = trimmed.split(separator: " ")
        let day = pieces[0].replacingOccurrences(of: ":", with: "-")
        guard pieces.count > 1 else { return day }
        let clock = pieces[1].split(separator: ":")
        guard clock.count >= 2 else { return day }
        return "\(day) \(clock[0]):\(clock[1])"
    }

    public static func camera(make: String?, model: String?) -> String? {
        let make = cleaned(make)
        let model = cleaned(model)
        switch (make, model) {
        case let (make?, model?):
            if model.localizedCaseInsensitiveContains(make) { return model }
            return "\(make) \(model)"
        case let (make?, nil):
            return make
        case let (nil, model?):
            return model
        default:
            return nil
        }
    }

    public static func lens(_ raw: String?, camera: String?) -> String? {
        guard let lens = cleaned(raw) else { return nil }
        if let camera, lens.caseInsensitiveCompare(camera) == .orderedSame { return nil }
        return lens
    }

    public static func aperture(_ value: Double) -> String? {
        guard value > 0 else { return nil }
        if value == floor(value) { return "f/\(Int(value))" }
        return String(format: "f/%.1f", value)
    }

    public static func shutter(_ seconds: Double) -> String? {
        guard seconds > 0 else { return nil }
        if seconds >= 1 {
            if seconds == floor(seconds) { return "\(Int(seconds))s" }
            return String(format: "%.1fs", seconds)
        }
        let denominator = max(1, Int((1.0 / seconds).rounded()))
        return "1/\(denominator)"
    }

    public static func iso(_ value: Int) -> String? {
        guard value > 0 else { return nil }
        return "\(value)"
    }

    public static func focalLength(_ millimeters: Double) -> String? {
        guard millimeters > 0 else { return nil }
        if millimeters == floor(millimeters) { return "\(Int(millimeters))mm" }
        return String(format: "%.1fmm", millimeters)
    }

    public static func pixelSize(width: Int, height: Int) -> String? {
        guard width > 0, height > 0 else { return nil }
        return "\(width)×\(height)"
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

public enum CaptureInfoReader {
    public static func load(url: URL) -> CaptureInfo {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return CaptureInfo()
        }
        return parse(props)
    }

    public static func parse(_ props: [CFString: Any]) -> CaptureInfo {
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let camera = CaptureInfoFormatter.camera(
            make: tiff?[kCGImagePropertyTIFFMake] as? String,
            model: tiff?[kCGImagePropertyTIFFModel] as? String
        )
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        return CaptureInfo(
            capturedAt: (exif?[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(CaptureInfoFormatter.date),
            camera: camera,
            lens: CaptureInfoFormatter.lens(exif?[kCGImagePropertyExifLensModel] as? String, camera: camera),
            aperture: number(exif?[kCGImagePropertyExifFNumber]).flatMap(CaptureInfoFormatter.aperture),
            shutter: number(exif?[kCGImagePropertyExifExposureTime]).flatMap(CaptureInfoFormatter.shutter),
            iso: isoValue(exif).flatMap(CaptureInfoFormatter.iso),
            focalLength: number(exif?[kCGImagePropertyExifFocalLength]).flatMap(CaptureInfoFormatter.focalLength),
            pixelSize: CaptureInfoFormatter.pixelSize(width: width ?? 0, height: height ?? 0)
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private static func isoValue(_ exif: [CFString: Any]?) -> Int? {
        if let numbers = exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber] {
            return numbers.first?.intValue
        }
        if let numbers = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int] {
            return numbers.first
        }
        return nil
    }
}
