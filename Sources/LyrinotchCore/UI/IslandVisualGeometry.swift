import CoreGraphics
import Foundation

/// Drawn island size shared by `NotchOverlayView` and `NotchOverlayController` hit-testing.
///
/// Keeping one formula prevents the pill from outgrowing the hit rect (missed edge clicks)
/// or undersizing the expanded body (lyrics/scrubber clipping).
public enum IslandVisualGeometry: Sendable {
    public static let collapsedLyricLipHeight: CGFloat = 26
    public static let mediaCapsuleHeight: CGFloat = 44
    /// Floating card top padding above the capsule.
    public static let floatingTopPadding: CGFloat = 10
    /// Expanded floating vertical padding (top + bottom).
    public static let floatingExpandedVerticalPadding: CGFloat = 28
    public static let maxIslandExtraWidth: CGFloat = 120
    public static let maxExpandedWidth: CGFloat = 680
    public static let maxFloatingExpandedContentWidth: CGFloat = 560

    public static func clampedExtraWidth(_ value: CGFloat) -> CGFloat {
        min(maxIslandExtraWidth, max(0, value))
    }

    public static func closedNotchWidth(deviceNotch: CGSize) -> CGFloat {
        max(140, deviceNotch.width)
    }

    public static func closedNotchHeight(deviceNotch: CGSize) -> CGFloat {
        max(28, deviceNotch.height)
    }

    public static func notchWingArtSize(deviceNotch: CGSize) -> CGFloat {
        max(18, min(26, closedNotchHeight(deviceNotch: deviceNotch) - 4))
    }

    public static func notchWingWidth(deviceNotch: CGSize) -> CGFloat {
        max(40, notchWingArtSize(deviceNotch: deviceNotch) + 16)
    }

    /// Expanded body budget: header + lyrics ± adjacent/translation + scrubber + transport.
    ///
    /// Keep the common no-translation state compact. Translation gets its own
    /// allowance instead of leaving that space empty for every track.
    public static func expandedBodyHeight(
        showAdjacentLines: Bool,
        hasTranslation: Bool = false
    ) -> CGFloat {
        let base: CGFloat = showAdjacentLines ? 232 : 200
        return base + (hasTranslation ? 40 : 0)
    }

    public static func closedNotchTotalWidth(
        deviceNotch: CGSize,
        islandExtraWidth: CGFloat
    ) -> CGFloat {
        let extra = clampedExtraWidth(islandExtraWidth)
        return closedNotchWidth(deviceNotch: deviceNotch)
            + notchWingWidth(deviceNotch: deviceNotch) * 2
            + extra
    }

    public static func openedNotchWidth(
        deviceNotch: CGSize,
        islandExtraWidth: CGFloat
    ) -> CGFloat {
        let extra = clampedExtraWidth(islandExtraWidth)
        let housing = closedNotchWidth(deviceNotch: deviceNotch)
        return min(maxExpandedWidth, max(housing + 240, 460) + extra)
    }

    /// Floating collapsed width upper bound when lyric text metrics are unavailable (hit-test).
    public static func floatingCollapsedMaxWidth(islandExtraWidth: CGFloat) -> CGFloat {
        min(520, max(260, 320 + clampedExtraWidth(islandExtraWidth)))
    }

    public static func floatingExpandedWidth(islandExtraWidth: CGFloat) -> CGFloat {
        min(600, maxFloatingExpandedContentWidth) + clampedExtraWidth(islandExtraWidth)
    }

    /// Visual island size used for hover / click / `hitTest` (must match the drawn shell).
    public static func visualSize(
        presentation: OverlayPresentationStyle,
        mode: IslandMode,
        deviceNotch: CGSize,
        islandExtraWidth: CGFloat,
        showAdjacentLines: Bool,
        hasTranslation: Bool = false
    ) -> CGSize {
        let extra = clampedExtraWidth(islandExtraWidth)
        let body = expandedBodyHeight(
            showAdjacentLines: showAdjacentLines,
            hasTranslation: hasTranslation
        )
        switch presentation {
        case .notchIsland:
            let housingH = closedNotchHeight(deviceNotch: deviceNotch)
            switch mode {
            case .collapsed:
                return CGSize(
                    width: closedNotchTotalWidth(deviceNotch: deviceNotch, islandExtraWidth: extra),
                    height: housingH + collapsedLyricLipHeight
                )
            case .expanded:
                return CGSize(
                    width: openedNotchWidth(deviceNotch: deviceNotch, islandExtraWidth: extra),
                    height: housingH + body
                )
            }
        case .floatingHUD:
            switch mode {
            case .collapsed:
                return CGSize(
                    width: floatingCollapsedMaxWidth(islandExtraWidth: extra),
                    height: floatingTopPadding + mediaCapsuleHeight
                )
            case .expanded:
                // Header padding + expanded body frame (+8 matches view).
                return CGSize(
                    width: floatingExpandedWidth(islandExtraWidth: extra),
                    height: floatingTopPadding + floatingExpandedVerticalPadding + body + 8
                )
            }
        }
    }

    /// Transparent panel canvas — large enough for the **expanded** island + spring overshoot.
    public static func contentSize(
        presentation: OverlayPresentationStyle,
        deviceNotch: CGSize,
        islandExtraWidth: CGFloat,
        showAdjacentLines: Bool,
        hasTranslation: Bool = false
    ) -> CGSize {
        let expanded = visualSize(
            presentation: presentation,
            mode: .expanded,
            deviceNotch: deviceNotch,
            islandExtraWidth: islandExtraWidth,
            showAdjacentLines: showAdjacentLines,
            hasTranslation: hasTranslation
        )
        // Margin for spring morph and outer glow without resizing the NSPanel.
        let padW: CGFloat = 24
        let padH: CGFloat = 28
        switch presentation {
        case .notchIsland:
            return CGSize(
                width: min(720, expanded.width + padW),
                height: min(460, max(420, expanded.height + padH))
            )
        case .floatingHUD:
            return CGSize(
                width: min(640, expanded.width + padW),
                height: min(440, max(400, expanded.height + padH))
            )
        }
    }
}
