import AppKit
import SwiftUI

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

    // MARK: 颜色
    let thumbnailPlaceholder = Color.gray.opacity(0.15)
    let recentRowFill = Color.gray.opacity(0.08)
    let searchFieldFill = Color.gray.opacity(0.12)
    let selectionFill = Color.accentColor.opacity(0.18)
    let selectionStroke = Color.accentColor
    let selectionStrokeWidth: CGFloat = 2
    let focusStroke = Color.accentColor.opacity(0.65)
    let hoverStroke = Color.primary.opacity(0.18)
    let viewerCanvas = Color(nsColor: .underPageBackgroundColor)

    func badgeBackground(isRaw: Bool) -> Color {
        isRaw ? Color.orange.opacity(0.95) : Color.black.opacity(0.55)
    }

    func badgeForeground(isRaw: Bool) -> Color {
        isRaw ? .black.opacity(0.85) : .white
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
