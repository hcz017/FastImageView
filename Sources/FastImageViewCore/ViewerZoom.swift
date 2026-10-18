import Foundation

public enum ViewerZoom: Equatable, Sendable {
    case fit
    case actual
    /// Magnification relative to fit-to-window. 1 means the whole image is visible.
    case multiple(Double)
}

public struct ViewerLayout: Equatable, Sendable {
    public var contentWidth: Double
    public var contentHeight: Double
    public var viewportWidth: Double
    public var viewportHeight: Double
    public var fitScale: Double

    public init(contentWidth: Double, contentHeight: Double, viewportWidth: Double, viewportHeight: Double, fitScale: Double) {
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.fitScale = fitScale
    }
}

public struct ImagePan: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public static let zero = ImagePan(x: 0, y: 0)

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static func clamped(
        x: Double,
        y: Double,
        contentWidth: Double,
        contentHeight: Double,
        viewportWidth: Double,
        viewportHeight: Double
    ) -> ImagePan {
        let maxX = max(0, (contentWidth - viewportWidth) / 2)
        let maxY = max(0, (contentHeight - viewportHeight) / 2)
        return ImagePan(
            x: min(max(x, -maxX), maxX),
            y: min(max(y, -maxY), maxY)
        )
    }
}

public struct ImagePixelSize: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// ImageIO pixel width/height are storage pixels; orientations 5–8 display swapped, matching thumbnails created with transform.
    public static func oriented(width: Int, height: Int, orientation: Int) -> ImagePixelSize {
        switch orientation {
        case 5, 6, 7, 8:
            return ImagePixelSize(width: height, height: width)
        default:
            return ImagePixelSize(width: width, height: height)
        }
    }
}

/// Layout uses the file's true pixels when known, so a larger decode does not change the frame.
public enum ViewerImageSizing {
    public static func layoutSize(
        decodedWidth: Int,
        decodedHeight: Int,
        source: ImagePixelSize?
    ) -> ImagePixelSize {
        if let source, source.width > 0, source.height > 0 {
            return source
        }
        return ImagePixelSize(width: decodedWidth, height: decodedHeight)
    }

    public static func isUpscalingPreview(
        decodedWidth: Int,
        decodedHeight: Int,
        layout: ImagePixelSize
    ) -> Bool {
        decodedWidth < layout.width || decodedHeight < layout.height
    }
}

public enum ZoomMath {
    public static let minimum = 0.05
    public static let maximum = 8.0
    public static let step = 1.25
    public static let fitEpsilon = 0.02

    public static func clamp(_ multiple: Double) -> Double {
        min(max(multiple, minimum), maximum)
    }

    public static func isFit(_ multiple: Double) -> Bool {
        abs(multiple - 1) < fitEpsilon
    }

    public static func stepped(_ multiple: Double, direction: Int) -> Double {
        guard direction != 0 else { return clamp(multiple) }
        let factor = direction > 0 ? step : (1 / step)
        return clamp(multiple * factor)
    }

    public static func applyingMagnify(multiple: Double, magnification: Double) -> Double {
        clamp(multiple * (1 + magnification))
    }

    public static func applyingScroll(multiple: Double, deltaY: Double) -> Double {
        guard deltaY != 0 else { return clamp(multiple) }
        return clamp(multiple * pow(1.002, deltaY))
    }

    public static func fitScale(imageWidth: Double, imageHeight: Double, viewportWidth: Double, viewportHeight: Double) -> Double {
        guard imageWidth > 0, imageHeight > 0, viewportWidth > 0, viewportHeight > 0 else { return 1 }
        return min(viewportWidth / imageWidth, viewportHeight / imageHeight)
    }

    public static func actualMultiple(fitScale: Double) -> Double {
        guard fitScale > 0 else { return 1 }
        return 1 / fitScale
    }

    public static func displayScale(fitScale: Double, multiple: Double) -> Double {
        fitScale * multiple
    }

    public static func prefersPan(contentWidth: Double, contentHeight: Double, viewportWidth: Double, viewportHeight: Double) -> Bool {
        contentWidth > viewportWidth + 1 || contentHeight > viewportHeight + 1
    }
}
