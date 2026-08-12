import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Visual preferences for the notch lyrics overlay (Island HUD defaults).
public struct OverlayAppearance: Sendable, Equatable {
    /// Background strength (0…1). Glass tint density or classic scrim strength.
    public var opacity: Double
    /// Primary lyric font size in points.
    public var fontSize: Double
    public var showTrackTitle: Bool
    /// Show previous / next lyric lines faintly.
    public var showAdjacentLines: Bool
    /// Ignore mouse events so clicks pass through.
    public var clickThrough: Bool
    /// Apply Liquid Glass on the **dynamic-island** (notched) presentation.
    public var liquidGlassOnNotch: Bool
    /// Apply Liquid Glass on the **floating HUD** (non-notch) presentation.
    public var liquidGlassOnFloating: Bool
    /// When Liquid Glass is on for a surface: clear (透明) or tinted (色調).
    public var glassVariant: LiquidGlassVariant

    public init(
        opacity: Double = 0.88,
        fontSize: Double = 15,
        showTrackTitle: Bool = false,
        showAdjacentLines: Bool = false,
        clickThrough: Bool = true,
        liquidGlassOnNotch: Bool = false,
        liquidGlassOnFloating: Bool = false,
        glassVariant: LiquidGlassVariant = .tinted
    ) {
        self.opacity = min(1, max(0.2, opacity))
        self.fontSize = min(24, max(12, fontSize))
        self.showTrackTitle = showTrackTitle
        self.showAdjacentLines = showAdjacentLines
        self.clickThrough = clickThrough
        self.liquidGlassOnNotch = liquidGlassOnNotch
        self.liquidGlassOnFloating = liquidGlassOnFloating
        self.glassVariant = glassVariant
    }

    public static let `default` = OverlayAppearance()

    /// True if any presentation uses Liquid Glass (for menu “any glass on” hints).
    public var usesLiquidGlassAnywhere: Bool {
        liquidGlassOnNotch || liquidGlassOnFloating
    }

    public func usesLiquidGlass(for presentation: OverlayPresentationStyle) -> Bool {
        switch presentation {
        case .notchIsland: return liquidGlassOnNotch
        case .floatingHUD: return liquidGlassOnFloating
        }
    }
}
