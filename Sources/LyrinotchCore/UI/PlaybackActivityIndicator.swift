import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// Equalizer bars for Dynamic Island–style media chrome (usually on the trailing edge).
public struct PlaybackActivityIndicator: View {
    public var isPlaying: Bool
    public var isActive: Bool
    /// Compact bars for tight island height.
    public var compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isPlaying: Bool, isActive: Bool = true, compact: Bool = false) {
        self.isPlaying = isPlaying
        self.isActive = isActive
        self.compact = compact
    }

    public var body: some View {
        Group {
            if isPlaying {
                SmoothEqualizer(compact: compact, paused: reduceMotion)
            } else if isActive {
                // Idle: short static bars so the pill keeps balance when paused mid-transition.
                SmoothEqualizer(compact: compact, paused: true)
                    .opacity(0.35)
            } else {
                Color.clear
            }
        }
        .frame(width: compact ? 16 : 20, height: compact ? 14 : 16)
        .accessibilityLabel(
            L10n.t(isPlaying ? "playback.playing" : "playback.paused")
        )
    }
}

// MARK: - Smooth equalizer

/// Soft, continuous bar motion (less jumpy than discrete keyframes).
private struct SmoothEqualizer: View {
    var compact: Bool = false
    var paused: Bool = false

    private var barCount: Int { compact ? 4 : 4 }
    private var barWidth: CGFloat { compact ? 2.0 : 2.2 }
    private var spacing: CGFloat { compact ? 1.6 : 2.0 }
    private var maxHeight: CGFloat { compact ? 12 : 13 }
    private var minHeight: CGFloat { compact ? 2.5 : 3 }

    private let phases: [Double] = [0.0, 0.55, 0.2, 0.85]
    private let speeds: [Double] = [1.15, 1.45, 1.05, 1.35]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
            let t = paused ? 0 : context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(barGradient)
                        .frame(width: barWidth, height: paused ? staticHeight(index) : height(for: index, at: t))
                        .shadow(color: .white.opacity(0.25), radius: 1.2, y: 0)
                }
            }
            .frame(width: compact ? 14 : 18, height: maxHeight, alignment: .center)
        }
    }

    private func staticHeight(_ index: Int) -> CGFloat {
        let steps: [CGFloat] = [0.45, 0.9, 0.55, 0.75]
        return minHeight + (maxHeight - minHeight) * steps[index % steps.count]
    }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.98),
                Color.white.opacity(0.72)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        let phase = phases[index % phases.count]
        let speed = speeds[index % speeds.count]
        // Two layered sines → organic, non-mechanical motion.
        let a = sin(time * speed * 2.4 * .pi + phase * .pi * 2)
        let b = sin(time * speed * 1.3 * .pi + phase * .pi)
        let mixed = (a * 0.65 + b * 0.35)
        // Map [-1, 1] → [0, 1] with a gentle curve.
        let normalized = (mixed + 1) / 2
        let eased = 0.15 + 0.85 * (normalized * normalized * (3 - 2 * normalized))
        return minHeight + (maxHeight - minHeight) * eased
    }
}

#endif
