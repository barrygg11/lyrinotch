import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// Overall surface treatment for the overlay chrome.
public enum OverlaySurfaceStyle: String, Codable, Sendable, CaseIterable, Equatable {
    /// Original solid black island / dark card.
    case classic
    /// Apple Liquid Glass–style material.
    case liquidGlass

    public var displayNameZH: String {
        switch self {
        case .classic: return "經典"
        case .liquidGlass: return "Liquid Glass"
        }
    }
}

/// Liquid Glass–inspired chrome for custom shapes (material + tint; portable SDKs).
public enum LiquidGlassVariant: String, Codable, Sendable, CaseIterable, Equatable {
    /// Clearer glass — more of the wallpaper shows through.
    case clear
    /// Tinted glass — slightly denser, more legible (default).
    case tinted

    public var displayNameZH: String {
        switch self {
        case .clear: return "透明"
        case .tinted: return "色調"
        }
    }
}

public struct LiquidGlassChrome<S: Shape>: ViewModifier {
    public var shape: S
    public var variant: LiquidGlassVariant
    /// 0…1 — how strong the dark tint is (maps from appearance.opacity).
    public var intensity: Double

    public init(shape: S, variant: LiquidGlassVariant = .tinted, intensity: Double = 0.55) {
        self.shape = shape
        self.variant = variant
        self.intensity = min(1, max(0.15, intensity))
    }

    public func body(content: Content) -> some View {
        content
            .background { glassBackground }
            .clipShape(shape)
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(variant == .clear ? 0.4 : 0.28),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
    }

    /// Material + tint fallback.
    ///
    /// Note: Apple’s `glassEffect` API only exists in **newer SDKs** (macOS 26+).
    /// GitHub Actions `macos-14` / many Xcode 15–16 toolchains cannot *compile*
    /// references to that symbol even inside `#available`, so we always use the
    /// material path for portable open-source builds. Looks good on macOS 14+.
    @ViewBuilder
    private var glassBackground: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(variant == .clear ? 0.18 : 0.10),
                        Color.white.opacity(0.02),
                        Color.black.opacity(variant == .tinted ? 0.22 + intensity * 0.35 : 0.12 + intensity * 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var shadowOpacity: Double {
        variant == .tinted ? 0.28 : 0.18
    }

    private var shadowRadius: CGFloat { 12 }
    private var shadowY: CGFloat { 4 }
}

public extension View {
    func liquidGlass<S: Shape>(
        in shape: S,
        variant: LiquidGlassVariant = .tinted,
        intensity: Double = 0.55
    ) -> some View {
        modifier(LiquidGlassChrome(shape: shape, variant: variant, intensity: intensity))
    }
}
#endif
