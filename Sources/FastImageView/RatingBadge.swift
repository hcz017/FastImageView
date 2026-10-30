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
            // 尖角两侧从尖端引向圆的切线，与圆顺滑相接，避免直线与圆弧
            // 交接处的断层。圆弧用折线逼近，不依赖 addArc 的绕向语义。
            let tangent = acos(inner / outer)
            let rightTip = CGPoint(x: center.x + outer, y: center.y)
            let leftTip = CGPoint(x: center.x - outer, y: center.y)
            func circlePoint(_ angle: CGFloat) -> CGPoint {
                CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle))
            }
            func appendArc(from start: CGFloat, to end: CGFloat) {
                let segments = 24
                for index in 1...segments {
                    let angle = start + (end - start) * CGFloat(index) / CGFloat(segments)
                    path.addLine(to: circlePoint(angle))
                }
            }
            path.move(to: rightTip)
            path.addLine(to: circlePoint(tangent))
            appendArc(from: tangent, to: .pi - tangent)
            path.addLine(to: leftTip)
            path.addLine(to: circlePoint(.pi + tangent))
            appendArc(from: .pi + tangent, to: 2 * .pi - tangent)
            path.closeSubpath()
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
