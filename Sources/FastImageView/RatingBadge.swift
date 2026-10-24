import SwiftUI

/// 分级徽标：1 级圆形，2 级圆 + 左右尖角，3–5 级为对应角数的星形。
struct RatingBadge: View {
    @Environment(\.appTheme) private var theme
    let level: Int
    var size: CGFloat?
    var showsShadow = true

    var body: some View {
        RatingBadgeShape(level: level)
            .fill(theme.ratingColor(level))
            .frame(width: size ?? theme.badgeHeight, height: size ?? theme.badgeHeight)
            .shadow(
                color: showsShadow ? theme.ratingBadgeShadow : .clear,
                radius: theme.ratingBadgeShadowRadius
            )
            .accessibilityLabel("分级 \(level)")
    }
}

struct RatingBadgeShape: Shape {
    let level: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        switch level {
        case 1:
            var path = Path()
            path.addEllipse(in: circleRect(center: center, radius: outer * 0.5))
            return path
        case 2:
            var path = Path()
            let inner = outer * 0.42
            path.addEllipse(in: circleRect(center: center, radius: inner))
            let baseAngle = CGFloat(35 * Double.pi / 180)
            for direction: CGFloat in [1, -1] {
                path.move(to: CGPoint(x: center.x + direction * outer, y: center.y))
                path.addLine(to: CGPoint(
                    x: center.x + direction * inner * cos(baseAngle),
                    y: center.y + inner * sin(baseAngle)
                ))
                path.addLine(to: CGPoint(
                    x: center.x + direction * inner * cos(baseAngle),
                    y: center.y - inner * sin(baseAngle)
                ))
                path.closeSubpath()
            }
            return path
        default:
            var path = Path()
            let points = max(level, 3) * 2
            for index in 0..<points {
                let radius = index.isMultiple(of: 2) ? outer : outer * 0.45
                let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / CGFloat(max(level, 3))
                let point = CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
            return path
        }
    }

    private func circleRect(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
}
