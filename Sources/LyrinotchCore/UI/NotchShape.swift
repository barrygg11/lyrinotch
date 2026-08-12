import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// Camera-housing inspired path used by vibe-notch / boring.notch style overlays.
/// Not an Apple system API — pure SwiftUI shape that *looks* like the hardware notch.
public struct NotchShape: Shape {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat

    public init(topCornerRadius: CGFloat = 6, bottomCornerRadius: CGFloat = 14) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}
#endif
