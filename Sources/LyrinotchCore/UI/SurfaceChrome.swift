#if canImport(SwiftUI)
import SwiftUI

/// Classic solid black or Liquid Glass for the current presentation surface.
struct SurfaceChrome<S: Shape>: ViewModifier {
    var shape: S
    var appearance: OverlayAppearance
    var useLiquidGlass: Bool
    var solidTopHeight: CGFloat

    private var intensity: Double {
        min(1, max(0.15, appearance.opacity + (useLiquidGlass ? 0.08 : 0)))
    }

    private var variant: LiquidGlassVariant { appearance.glassVariant }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                        .opacity(useLiquidGlass ? 1 : 0)
                    shape.fill(glassTint)
                        .opacity(useLiquidGlass ? 1 : 0)
                    shape.fill(Color.black.opacity(0.92 + appearance.opacity * 0.08))
                        .opacity(useLiquidGlass ? 0 : 1)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(borderGradient, lineWidth: useLiquidGlass ? 0.8 : 0.6)
            }
            .overlay(alignment: .top) {
                if solidTopHeight > 0 {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: solidTopHeight + (useLiquidGlass ? 1 : 2))
                        .frame(maxWidth: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                }
            }
            .shadow(
                color: Color.black.opacity(useLiquidGlass ? (variant == .tinted ? 0.28 : 0.18) : 0.35),
                radius: useLiquidGlass ? 12 : 8,
                y: useLiquidGlass ? 4 : 3
            )
            .animation(nil, value: useLiquidGlass)
            .animation(nil, value: variant)
    }

    private var glassTint: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(variant == .clear ? 0.18 : 0.10),
                Color.white.opacity(0.02),
                Color.black.opacity(
                    variant == .tinted
                        ? 0.22 + intensity * 0.35
                        : 0.12 + intensity * 0.15
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderGradient: LinearGradient {
        if useLiquidGlass {
            return LinearGradient(
                colors: [
                    Color.white.opacity(variant == .clear ? 0.4 : 0.28),
                    Color.white.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [Color.white.opacity(0.08), Color.white.opacity(0.08)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
#endif
