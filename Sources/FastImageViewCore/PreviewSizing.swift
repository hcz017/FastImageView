import ImageIO

public enum ViewerFit: Equatable, Sendable {
    case fit
    case actual
}

public enum PreviewMaxPixel {
    public static let thumbnail = 400
    public static let rawActualCap = 16384

    public static func viewer(fit: ViewerFit, screenLongEdge: Int, isRaw: Bool) -> Int {
        let _ = isRaw
        return viewer(zoom: fit == .fit ? .fit : .actual, screenLongEdge: screenLongEdge)
    }

    public static func viewer(zoom: ViewerZoom, screenLongEdge: Int) -> Int {
        switch zoom {
        case .fit:
            return screenLongEdge
        case .actual, .multiple:
            return rawActualCap
        }
    }
}

public enum ImageIOThumbnailOptions {
    public static let imageIndex = 0

    public static func dictionary(maxPixelSize: Int) -> [CFString: Any] {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
    }
}
