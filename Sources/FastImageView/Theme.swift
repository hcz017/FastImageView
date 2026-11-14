import AppKit
import SwiftUI
import FastImageViewCore

/// 集中管理配色、间距、圆角等视觉常量；视图里不再出现硬编码值。
struct AppTheme {
    // MARK: 间距（4/8/12/16/24 增量）
    let spacingXS: CGFloat = 4
    let spacingSM: CGFloat = 8
    let spacingMD: CGFloat = 12
    let spacingLG: CGFloat = 16
    let spacingXL: CGFloat = 24

    // MARK: 圆角
    let radiusBadge: CGFloat = 4
    let radiusSmall: CGFloat = 8
    let radiusLarge: CGFloat = 12

    // MARK: 网格
    let tileMinWidth: CGFloat = 168
    let tileMaxWidth: CGFloat = 220
    let tileAspectRatio: CGFloat = 4.0 / 3.0
    let gridSpacing: CGFloat = 12

    // MARK: 大图
    /// 图片信息浮层按内容收窄，超长字段在此宽度内换行。
    let captureInfoMaxWidth: CGFloat = 250

    // MARK: 格式筛选菜单
    /// 面板最小宽度；格式徽标最长 4 个字符，够放下「全部格式」即可。
    let formatMenuWidth: CGFloat = 120
    /// 入口按钮标题占位宽度，避免标题随筛选状态变化时工具栏抖动。
    let formatMenuTitleMinWidth: CGFloat = 72
    /// 行尾勾选列固定宽度，保证各行右边缘对齐。
    let menuCheckmarkWidth: CGFloat = 16

    // MARK: 分级
    /// 缩略图左下角格式徽标与右下角分级徽标共用的高度。
    let badgeHeight: CGFloat = 21
    /// 分级徽标颜色，缩略图与筛选面板一致；后续可按等级区分。
    let ratingBadgeColor = Color(nsColor: .systemYellow)
    let ratingBadgeShadow = Color.black.opacity(0.45)
    let ratingBadgeShadowRadius: CGFloat = 1.5
    /// 大图里设置/取消分级后，右下角反馈徽标比缩略图徽标更大，便于看见。
    let ratingFeedbackSize: CGFloat = 34

    func ratingColor(_ level: Int) -> Color {
        ratingBadgeColor
    }

    // MARK: 颜色
    let thumbnailPlaceholder = Color.gray.opacity(0.15)
    let recentRowFill = Color.gray.opacity(0.08)
    let recentRowHoverFill = Color.gray.opacity(0.14)
    let selectionFill = Color.accentColor.opacity(0.18)
    let selectionStroke = Color.accentColor
    let selectionStrokeWidth: CGFloat = 2
    let hoverStroke = Color.primary.opacity(0.18)
    let viewerCanvas = Color(nsColor: .underPageBackgroundColor)

    func badgeBackground(for format: ImageFormat) -> Color {
        switch format {
        case .jpeg:
            return Color(red: 0.18, green: 0.42, blue: 0.86).opacity(0.92)
        case .png:
            return Color(red: 0.12, green: 0.55, blue: 0.36).opacity(0.92)
        case .heic:
            return Color(red: 0.45, green: 0.28, blue: 0.78).opacity(0.92)
        case .gif:
            return Color(red: 0.78, green: 0.22, blue: 0.48).opacity(0.92)
        case .tiff:
            return Color(red: 0.12, green: 0.52, blue: 0.58).opacity(0.92)
        case .webp:
            return Color(red: 0.18, green: 0.58, blue: 0.72).opacity(0.92)
        case .bmp:
            return Color(red: 0.35, green: 0.40, blue: 0.52).opacity(0.92)
        case .nef, .nrw, .cr2, .cr3, .arw, .sr2, .srf, .raf, .orf, .rw2, .dng, .pef:
            return Color.orange.opacity(0.95)
        }
    }

    func badgeForeground(for format: ImageFormat) -> Color {
        format.isRaw ? .black.opacity(0.85) : .white
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme()
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
