import Foundation

/// Parses LRC timed lyrics into `[LyricLine]`.
public enum LRCParser {
    /// Matches `[mm:ss.xx]` or `[mm:ss.xxx]` or `[mm:ss]` optionally repeated.
    private static let linePattern = try! NSRegularExpression(
        pattern: #"^((?:\[\d{1,2}:\d{2}(?:\.\d{1,3})?\])+)(.*)$"#,
        options: []
    )

    private static let tagPattern = try! NSRegularExpression(
        pattern: #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#,
        options: []
    )

    private static let offsetPattern = try! NSRegularExpression(
        pattern: #"\[offset:\s*([+-]?\d+)\]"#,
        options: [.caseInsensitive]
    )

    private static func parsedEmbeddedOffsetSeconds(in lrc: String) -> Double? {
        let ns = lrc as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = offsetPattern.firstMatch(in: lrc, options: [], range: full),
              match.numberOfRanges >= 2
        else { return nil }
        guard let ms = Double(ns.substring(with: match.range(at: 1))), ms.isFinite else {
            return nil
        }
        let seconds = ms / 1000.0
        guard seconds.isFinite,
              abs(seconds) <= LyricsInputLimits.maximumEmbeddedOffsetSeconds
        else { return nil }
        return seconds
    }

    /// Embedded `[offset:±ms]` shift (milliseconds added to every timestamp).
    /// Out-of-policy values are reported as zero for compatibility; `parse` rejects
    /// the document rather than silently changing its timeline.
    public static func embeddedOffsetSeconds(in lrc: String) -> Double {
        parsedEmbeddedOffsetSeconds(in: lrc) ?? 0
    }

    public static func parse(
        _ lrc: String,
        maximumLines: Int? = nil
    ) -> [LyricLine] {
        var result: [LyricLine] = []
        let hasOffsetTag = offsetPattern.firstMatch(
            in: lrc,
            options: [],
            range: NSRange(location: 0, length: (lrc as NSString).length)
        ) != nil
        guard !hasOffsetTag || parsedEmbeddedOffsetSeconds(in: lrc) != nil else {
            return []
        }
        let embeddedShift = parsedEmbeddedOffsetSeconds(in: lrc) ?? 0

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            guard let match = linePattern.firstMatch(in: line, options: [], range: full) else {
                continue
            }

            let tagsPart = ns.substring(with: match.range(at: 1))
            let text = ns.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip metadata tags like [ar:], [ti:], [al:] when they don't match time pattern.
            let tagNS = tagsPart as NSString
            let tagFull = NSRange(location: 0, length: tagNS.length)
            let tagMatches = tagPattern.matches(in: tagsPart, options: [], range: tagFull)
            guard !tagMatches.isEmpty else { continue }

            for tag in tagMatches {
                if let maximumLines, result.count >= maximumLines { break }
                let minutes = Double(tagNS.substring(with: tag.range(at: 1))) ?? 0
                let seconds = Double(tagNS.substring(with: tag.range(at: 2))) ?? 0
                var fraction = 0.0
                if tag.range(at: 3).location != NSNotFound {
                    let fracRaw = tagNS.substring(with: tag.range(at: 3))
                    // ".5" => 0.5, ".05" => 0.05, ".500" => 0.500
                    let padded = fracRaw.padding(toLength: 3, withPad: "0", startingAt: 0)
                    fraction = (Double(padded) ?? 0) / 1000.0
                }
                let time = minutes * 60 + seconds + fraction + embeddedShift
                guard let safeTime = LyricsInputLimits.validTimestamp(max(0, time)) else {
                    return []
                }
                result.append(LyricLine(time: safeTime, text: text))
            }
            if let maximumLines, result.count >= maximumLines { break }
        }

        return result.sorted { $0.time < $1.time }
    }
}
