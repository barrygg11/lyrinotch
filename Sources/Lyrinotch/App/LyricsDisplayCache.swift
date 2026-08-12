import Foundation
import LyrinotchCore

/// Memoizes timeline estimation and Chinese conversion used by the 10 Hz overlay path.
struct LyricsDisplayCache {
    private var rawDuration: TimeInterval?
    private var rawLines: [LyricLine] = []
    private var hasRawValue = false
    private var displayDuration: TimeInterval?
    private var displayTraditional = false
    private var displayLines: [LyricLine] = []
    private var hasDisplayValue = false

    mutating func invalidate() {
        hasRawValue = false
        hasDisplayValue = false
    }

    mutating func raw(snapshot: LyricsSnapshot, duration: TimeInterval?) -> [LyricLine] {
        if hasRawValue, rawDuration == duration { return rawLines }
        rawLines = snapshot.displayLines(duration: duration)
        rawDuration = duration
        hasRawValue = true
        hasDisplayValue = false
        return rawLines
    }

    mutating func display(
        snapshot: LyricsSnapshot,
        duration: TimeInterval?,
        traditional: Bool
    ) -> [LyricLine] {
        if hasDisplayValue,
           displayDuration == duration,
           displayTraditional == traditional
        {
            return displayLines
        }
        let source = raw(snapshot: snapshot, duration: duration)
        displayLines = traditional
            ? source.map {
                LyricLine(time: $0.time, text: TrackQueryNormalizer.traditionalChinese($0.text))
            }
            : source
        displayDuration = duration
        displayTraditional = traditional
        hasDisplayValue = true
        return displayLines
    }
}
