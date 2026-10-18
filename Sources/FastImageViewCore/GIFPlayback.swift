import CoreGraphics
import Foundation
import ImageIO

public enum GIFPlayback {
    public static let maxPixel = 1280
    public static let maxFrames = 180
    public static let minimumDelay = 0.1

    /// Browsers treat a delay under 2/100s as 0.1s. Unclamped delay wins when it is present.
    public static func delay(unclamped: Double?, fallback: Double?) -> Double {
        let value = unclamped ?? fallback ?? minimumDelay
        if value < 0.02 { return minimumDelay }
        return value
    }

    public static func index(elapsed: Double, delays: [Double]) -> Int {
        guard !delays.isEmpty else { return 0 }
        let total = delays.reduce(0, +)
        guard total > 0 else { return 0 }
        var time = elapsed.truncatingRemainder(dividingBy: total)
        if time < 0 { time += total }
        var cursor = 0.0
        for (index, delay) in delays.enumerated() {
            cursor += delay
            if time < cursor { return index }
        }
        return 0
    }
}

public struct GIFClipData: Sendable {
    public var frames: [CGImage]
    public var delays: [Double]

    public init(frames: [CGImage], delays: [Double]) {
        self.frames = frames
        self.delays = delays
    }
}

public enum GIFDecoder {
    public static func decode(url: URL, maxPixelSize: Int) -> GIFClipData? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = min(CGImageSourceGetCount(source), GIFPlayback.maxFrames)
        guard count > 1 else { return nil }
        var frames: [CGImage] = []
        var delays: [Double] = []
        frames.reserveCapacity(count)
        let options = ImageIOThumbnailOptions.dictionary(maxPixelSize: maxPixelSize) as CFDictionary
        for index in 0..<count {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options) else { continue }
            frames.append(image)
            delays.append(delay(at: index, source: source))
        }
        guard frames.count > 1, frames.count == delays.count else { return nil }
        return GIFClipData(frames: frames, delays: delays)
    }

    private static func delay(at index: Int, source: CGImageSource) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return GIFPlayback.minimumDelay
        }
        let unclamped = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
        let fallback = (gif[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
        return GIFPlayback.delay(unclamped: unclamped, fallback: fallback)
    }
}
