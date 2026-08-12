import CoreGraphics
import Foundation

public struct NotchBand: Equatable, Sendable {
    public var frame: CGRect
    public var isHardwareNotch: Bool

    public init(frame: CGRect, isHardwareNotch: Bool) {
        self.frame = frame
        self.isHardwareNotch = isHardwareNotch
    }

    public var midX: CGFloat { frame.midX }
    public var width: CGFloat { frame.width }
    public var height: CGFloat { frame.height }
    public var preferredCollapsedWidth: CGFloat {
        min(320, max(160, width + 36))
    }
}

/// Pure geometry used by the AppKit adapter and unit tests.
public enum NotchGeometryLogic {
    public static func band(
        screenFrame: CGRect,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?,
        safeAreaTop: CGFloat
    ) -> NotchBand? {
        if let left = auxiliaryTopLeft,
           let right = auxiliaryTopRight,
           left.width > 1,
           right.width > 1
        {
            let minX = left.maxX
            let maxX = right.minX
            let width = maxX - minX
            if width > 40, width < screenFrame.width * 0.45 {
                return NotchBand(
                    frame: CGRect(
                        x: minX,
                        y: max(left.minY, right.minY),
                        width: width,
                        height: max(left.height, right.height, safeAreaTop, 24)
                    ),
                    isHardwareNotch: true
                )
            }
        }

        guard safeAreaTop > 0 else { return nil }
        let width = min(200, max(140, screenFrame.width * 0.12))
        return NotchBand(
            frame: CGRect(
                x: screenFrame.midX - width / 2,
                y: screenFrame.maxY - safeAreaTop,
                width: width,
                height: safeAreaTop
            ),
            isHardwareNotch: false
        )
    }
}
