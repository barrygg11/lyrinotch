import Foundation

/// Applies only corrections that can be inferred safely from an LRC timeline.
///
/// The current playhead alone cannot reveal a lyric offset: verses, instrumental
/// breaks, and outros are not distributed uniformly across a song. Offset
/// correction therefore belongs to mic/manual calibration, not timeline shape.
public enum LyricTimelineAligner {
    public struct Result: Equatable, Sendable {
        /// Timestamps after duration scaling (and optional embedded LRC offset).
        public var lines: [LyricLine]
        /// Alignment returns zero here; retained for source compatibility.
        public var progressOffset: Double
        /// Scale applied to timestamps (`1` = unchanged).
        public var scale: Double
        /// Human-readable method applied, e.g. `scale:0.800`.
        public var method: String

        public init(lines: [LyricLine], progressOffset: Double, scale: Double, method: String) {
            self.lines = lines
            self.progressOffset = progressOffset
            self.scale = scale
            self.method = method
        }
    }

    /// Align synced lines to track duration. `playbackPosition` is retained for
    /// source compatibility and intentionally does not influence the result.
    public static func align(
        lines: [LyricLine],
        trackDuration: TimeInterval?,
        playbackPosition: TimeInterval? = nil
    ) -> Result {
        guard !lines.isEmpty else {
            return Result(lines: lines, progressOffset: 0, scale: 1, method: "empty")
        }

        var methods: [String] = []
        let scaled = durationScale(lines: lines, trackDuration: trackDuration)
        if abs(scaled.scale - 1) > 0.02 {
            methods.append(String(format: "scale:%.3f", scaled.scale))
        }
        _ = playbackPosition

        if methods.isEmpty { methods.append("passthrough") }
        return Result(
            lines: scaled.lines,
            progressOffset: 0,
            scale: scaled.scale,
            method: methods.joined(separator: "+")
        )
    }

    /// Compress timestamps only when lyrics extend beyond the track.
    ///
    /// A short lyric timeline is ambiguous (instrumental outro, partial lyrics,
    /// or an intentionally sparse file), so stretching it would create drift.
    public static func durationScale(
        lines: [LyricLine],
        trackDuration: TimeInterval?
    ) -> (lines: [LyricLine], scale: Double) {
        guard let duration = trackDuration, duration > 30, lines.count >= 3 else {
            return (lines, 1)
        }
        let nonEmpty = lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let last = nonEmpty.last?.time, last > 15 else {
            return (lines, 1)
        }

        let ratio = last / duration
        // A final line beyond 108% cannot fit this track. Short timelines are
        // deliberately preserved because long intros/outros are common.
        guard ratio > 1.08 else {
            return (lines, 1)
        }

        // Aim last lyric ~96% of track (leave short outro).
        let targetLast = duration * 0.96
        var scale = targetLast / last
        // Safety clamp avoids a wild warp when the selected LRC is unrelated.
        scale = max(0.65, scale)
        if abs(scale - 1) < 0.02 {
            return (lines, 1)
        }

        let out = lines.map { LyricLine(time: max(0, $0.time * scale), text: $0.text) }
        return (out, scale)
    }

    /// Progress-only offset inference was removed because it invents drift for
    /// songs with non-uniform lyric density. Retained as a zero-returning shim.
    @available(*, deprecated, message: "Song progress cannot safely infer a lyric offset")
    public static func progressOffset(
        lines: [LyricLine],
        trackDuration: TimeInterval,
        playbackPosition: TimeInterval
    ) -> Double {
        _ = lines
        _ = trackDuration
        _ = playbackPosition
        return 0
    }

    /// Blend a noisy calibration estimate into a session offset (EMA).
    public static func blendOffset(
        current: Double,
        sample: Double,
        alpha: Double = 0.28
    ) -> Double {
        guard abs(sample) >= 0.12 else {
            // Slowly decay toward 0 when signal says “already OK”.
            return current * (1 - alpha * 0.5)
        }
        let a = min(1, max(0.05, alpha))
        let blended = current * (1 - a) + sample * a
        return min(6.0, max(-6.0, blended))
    }

    @available(*, deprecated, renamed: "blendOffset(current:sample:alpha:)")
    public static func blendProgressOffset(
        current: Double,
        sample: Double,
        alpha: Double = 0.28
    ) -> Double {
        blendOffset(current: current, sample: sample, alpha: alpha)
    }
}
