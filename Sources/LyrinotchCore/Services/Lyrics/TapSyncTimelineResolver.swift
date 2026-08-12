import Foundation

/// Builds a monotonic, piecewise lyric timeline from sparse tap anchors.
public enum TapSyncTimelineResolver {
    public static func resolve(project: TapSyncProject) throws -> [LyricLine] {
        guard !project.anchors.isEmpty else { throw TapSyncProjectError.noAnchors }
        guard project.baseLyrics.timelineFingerprint(duration: project.trackDuration)
            == project.baseLyricsFingerprint
        else { throw TapSyncProjectError.lyricsFingerprintMismatch }

        let baseLines = sourceLines(for: project)
        guard baseLines.count == project.lineTexts.count, !baseLines.isEmpty else {
            throw TapSyncProjectError.corruptProject
        }

        let coordinates = monotonicCoordinates(for: baseLines)
        let times = resolvedTimes(
            coordinates: coordinates,
            anchors: project.anchors,
            duration: project.trackDuration
        )
        guard times.count == baseLines.count else {
            throw TapSyncProjectError.corruptProject
        }

        return zip(times, project.lineTexts).map { time, text in
            LyricLine(time: time, text: text)
        }
    }

    private static func sourceLines(for project: TapSyncProject) -> [LyricLine] {
        switch project.baseLyrics.availability {
        case .plain:
            return LyricsSnapshot.estimateTimedLines(
                from: project.baseLyrics.plainLines,
                duration: project.trackDuration
            )
        case .synced:
            return project.baseLyrics.lines
        default:
            return []
        }
    }

    /// Converts malformed/equal provider timestamps into stable increasing
    /// coordinates without changing any output anchor. Positive source gaps are
    /// retained, while missing gaps use the median source cadence (or 4 seconds).
    private static func monotonicCoordinates(for lines: [LyricLine]) -> [TimeInterval] {
        guard !lines.isEmpty else { return [] }
        let positiveGaps = zip(lines, lines.dropFirst()).compactMap { first, second -> Double? in
            let gap = second.time - first.time
            return gap.isFinite && gap > 0 ? gap : nil
        }.sorted()
        let fallbackGap: TimeInterval
        if positiveGaps.isEmpty {
            fallbackGap = 4
        } else {
            fallbackGap = positiveGaps[positiveGaps.count / 2]
        }

        var result = [TimeInterval](repeating: 0, count: lines.count)
        for index in 1..<lines.count {
            let rawGap = lines[index].time - lines[index - 1].time
            let gap = rawGap.isFinite && rawGap > 0 ? rawGap : fallbackGap
            result[index] = result[index - 1] + gap
        }
        return result
    }

    private static func resolvedTimes(
        coordinates: [TimeInterval],
        anchors: [TapSyncAnchor],
        duration: TimeInterval?
    ) -> [TimeInterval] {
        var result = [TimeInterval](repeating: 0, count: coordinates.count)
        let sorted = anchors.sorted { $0.lineIndex < $1.lineIndex }

        for anchor in sorted {
            result[anchor.lineIndex] = anchor.playbackTime
        }

        // Interpolate each bounded segment. Coordinate fractions preserve known
        // pauses in an existing synced source; plain lyrics naturally use an
        // even coordinate grid.
        if sorted.count > 1 {
            for pairIndex in 0..<(sorted.count - 1) {
                let lower = sorted[pairIndex]
                let upper = sorted[pairIndex + 1]
                guard upper.lineIndex - lower.lineIndex > 1 else { continue }
                let coordinateSpan = coordinates[upper.lineIndex] - coordinates[lower.lineIndex]
                for lineIndex in (lower.lineIndex + 1)..<upper.lineIndex {
                    let fraction: Double
                    if coordinateSpan > 0 {
                        fraction = (coordinates[lineIndex] - coordinates[lower.lineIndex])
                            / coordinateSpan
                    } else {
                        fraction = Double(lineIndex - lower.lineIndex)
                            / Double(upper.lineIndex - lower.lineIndex)
                    }
                    result[lineIndex] = lower.playbackTime
                        + (upper.playbackTime - lower.playbackTime) * fraction
                }
            }
        }

        let first = sorted[0]
        if first.lineIndex > 0 {
            let coordinateSpan = coordinates[first.lineIndex] - coordinates[0]
            var scale = extrapolationScale(atStartOf: sorted, coordinates: coordinates)
            if coordinateSpan > 0 {
                // Never invent negative song times; compress this unbounded
                // prefix if the first tap occurred earlier than extrapolated.
                scale = min(scale, first.playbackTime / coordinateSpan)
            }
            scale = max(0, scale)
            for lineIndex in 0..<first.lineIndex {
                result[lineIndex] = max(
                    0,
                    first.playbackTime
                        - (coordinates[first.lineIndex] - coordinates[lineIndex]) * scale
                )
            }
        }

        let last = sorted[sorted.count - 1]
        if last.lineIndex < coordinates.count - 1 {
            let coordinateSpan = coordinates[coordinates.count - 1] - coordinates[last.lineIndex]
            var scale = extrapolationScale(atEndOf: sorted, coordinates: coordinates)
            if let duration, coordinateSpan > 0, duration >= last.playbackTime {
                // Keep the generated tail inside the known song duration.
                scale = min(scale, (duration - last.playbackTime) / coordinateSpan)
            }
            scale = max(0, scale)
            for lineIndex in (last.lineIndex + 1)..<coordinates.count {
                result[lineIndex] = last.playbackTime
                    + (coordinates[lineIndex] - coordinates[last.lineIndex]) * scale
            }
        }

        return result
    }

    private static func extrapolationScale(
        atStartOf anchors: [TapSyncAnchor],
        coordinates: [TimeInterval]
    ) -> Double {
        guard anchors.count > 1 else { return 1 }
        return scale(between: anchors[0], and: anchors[1], coordinates: coordinates)
    }

    private static func extrapolationScale(
        atEndOf anchors: [TapSyncAnchor],
        coordinates: [TimeInterval]
    ) -> Double {
        guard anchors.count > 1 else { return 1 }
        return scale(
            between: anchors[anchors.count - 2],
            and: anchors[anchors.count - 1],
            coordinates: coordinates
        )
    }

    private static func scale(
        between first: TapSyncAnchor,
        and second: TapSyncAnchor,
        coordinates: [TimeInterval]
    ) -> Double {
        let coordinateSpan = coordinates[second.lineIndex] - coordinates[first.lineIndex]
        guard coordinateSpan > 0 else { return 1 }
        let measured = (second.playbackTime - first.playbackTime) / coordinateSpan
        // Bounded extrapolation avoids projecting one anomalous sparse segment
        // wildly across an unrecorded intro/outro. Bounded interpolation still
        // always uses the exact taps above.
        return min(5, max(0.05, measured))
    }
}
