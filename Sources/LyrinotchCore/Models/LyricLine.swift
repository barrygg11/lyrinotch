import Foundation

/// One timed lyric line (LRC-style).
public struct LyricLine: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(time)-\(text)" }
    /// Start time in seconds from track start.
    public var time: TimeInterval
    public var text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }

    public var timeString: String {
        guard time.isFinite, time >= 0, time < Double(Int.max - 1) else {
            return "--:--"
        }
        let total = Int(time.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Returns the active line index for a given playback position.
    public static func activeIndex(in lines: [LyricLine], at position: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var current: Int?
        for (index, line) in lines.enumerated() {
            if line.time <= position {
                current = index
            } else {
                break
            }
        }
        return current
    }

    /// First non-empty timed line strictly after the current lyric playhead.
    public static func nextNonEmpty(
        in lines: [LyricLine],
        after position: TimeInterval
    ) -> LyricLine? {
        lines.first { line in
            line.time > position
                && !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Whole seconds remaining until this line, rounded up for a stable countdown.
    public func secondsUntil(startingAt position: TimeInterval) -> Int {
        guard time.isFinite, position.isFinite else { return 0 }
        let remaining = time - position
        guard remaining.isFinite,
              remaining >= Double(Int.min + 1),
              remaining < Double(Int.max - 1)
        else { return 0 }
        return max(0, Int(ceil(remaining)))
    }
}
