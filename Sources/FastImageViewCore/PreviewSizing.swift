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

    /// 对比模式按格数均分屏幕长边；缩放后沿用单图的实际像素上限。
    public static func compare(zoom: ViewerZoom, panes: Int, screenLongEdge: Int) -> Int {
        switch zoom {
        case .fit:
            return max(1, screenLongEdge / max(panes, 1))
        case .actual, .multiple:
            return rawActualCap
        }
    }
}

public enum ImageIOThumbnailOptions {
    public static let imageIndex = 0

    /// - Parameter isRaw: 相机原片只走内嵌 JPEG 预览，避免全尺寸 RAW 解码。
    public static func dictionary(maxPixelSize: Int, isRaw: Bool = false) -> [CFString: Any] {
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        // RAW 用 `FromImageIfAbsent` 优先取内嵌预览：`FromImageAlways` 会按请求尺寸
        // 走不同的 RAW 渲染路径（8-bit P3 / 8-bit sRGB / 16-bit），缩放时颜色会跳变。
        options[isRaw
            ? kCGImageSourceCreateThumbnailFromImageIfAbsent
            : kCGImageSourceCreateThumbnailFromImageAlways] = true
        return options
    }
}
