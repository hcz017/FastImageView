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

    // MARK: 颜色
    let thumbnailPlaceholder = Color.gray.opacity(0.15)
    let recentRowFill = Color.gray.opacity(0.08)
    let searchFieldFill = Color.gray.opacity(0.12)
    let selectionFill = Color.accentColor.opacity(0.18)
    let selectionStroke = Color.accentColor
    let selectionStrokeWidth: CGFloat = 2

    func badgeBackground(isRaw: Bool) -> Color {
        isRaw ? Color.orange.opacity(0.92) : Color.black.opacity(0.55)
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
