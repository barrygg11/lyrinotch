import Foundation

/// Finds the best lyrics timeline offset by correlating audio onsets with LRC line times.
///
/// Convention matches `AppPreferences.lyricOffsetSeconds`:
/// `activePosition = playbackPosition + offset`
/// (positive → show later lines sooner).
public enum LyricOffsetAligner {
    public struct Result: Equatable, Sendable {
        /// Seconds to add to playback position when picking the active line.
        public var offset: Double
        /// 0…1 rough confidence (peak prominence).
        public var confidence: Double
        /// Peak score / mean score (for debugging).
        public var peakRatio: Double
        /// How many lyric lines landed on strong onsets.
        public var hits: Int

        public init(offset: Double, confidence: Double, peakRatio: Double, hits: Int = 0) {
            self.offset = offset
            self.confidence = confidence
            self.peakRatio = peakRatio
            self.hits = hits
        }
    }

    /// Convert a linear energy envelope into a non-negative onset strength series.
    public static func onsetStrength(fromEnergy energy: [Float]) -> [Float] {
        guard energy.count >= 2 else { return Array(repeating: 0, count: energy.count) }
        var out = [Float](repeating: 0, count: energy.count)
        // Median-ish noise floor from first second-ish of samples (or whole if short).
        let floorCount = min(energy.count, max(8, energy.count / 10))
        let sortedPrefix = energy.prefix(floorCount).sorted()
        let noiseFloor = sortedPrefix[sortedPrefix.count / 2]

        for i in 1..<energy.count {
            let prev = max(energy[i - 1], 1e-9)
            let cur = max(energy[i], 1e-9)
            // Relative rise above local noise.
            let rise = logf(cur) - logf(prev)
            let above = max(0, cur - noiseFloor * 1.4)
            out[i] = max(0, rise) * (0.35 + min(2.5, above * 40))
        }
        // 5-tap smooth
        if out.count >= 5 {
            var smooth = out
            for i in 2..<(out.count - 2) {
                smooth[i] = (
                    out[i - 2] + out[i - 1] * 2 + out[i] * 3 + out[i + 1] * 2 + out[i + 2]
                ) / 9
            }
            return smooth
        }
        return out
    }

    /// Search for the offset that best places lyric line onsets on audio onsets.
    ///
    /// This is a radius around the total offset already applied to the playhead,
    /// not an absolute clamp. A 2.5 second window keeps a clear +/-2 second
    /// correction away from the search boundary, where truncated peaks are unsafe.
    public static let micSearchRadius: TimeInterval = 2.5
    /// Compatibility alias for clients compiled against the old name. The aligner
    /// no longer clamps a total offset to this value.
    public static let micMaxAbsOffset: Double = micSearchRadius
    /// Compatibility gate for automatic offsets persisted by older app versions.
    public static let micPersistMinConfidence: Double = 0.65

    /// Lines in bilingual or romanized LRC files are often stacked at the same
    /// timestamp (or a few centiseconds apart). They represent one vocal onset,
    /// so calibration must not count or score them as independent evidence.
    public static let stackedLyricTimestampTolerance: TimeInterval = 0.20

    /// Returns valid, sorted lyric times with stacked lines collapsed to one
    /// singing point. The earliest timestamp in each cluster is retained.
    public static func distinctSingingPointTimes(
        from lyricTimes: [TimeInterval]
    ) -> [TimeInterval] {
        let sortedTimes = lyricTimes.filter { $0.isFinite && $0 >= 0 }.sorted()
        var distinctTimes: [TimeInterval] = []
        distinctTimes.reserveCapacity(sortedTimes.count)

        for time in sortedTimes {
            guard let previous = distinctTimes.last else {
                distinctTimes.append(time)
                continue
            }
            if time - previous > stackedLyricTimestampTolerance {
                distinctTimes.append(time)
            }
        }
        return distinctTimes
    }

    public static func bestOffset(
        onsetEnvelope: [Float],
        hopSeconds: Double,
        envelopeStartPlayback: TimeInterval,
        lyricTimes: [TimeInterval],
        currentTotalOffset: TimeInterval = 0,
        searchRadius: TimeInterval = micSearchRadius,
        step: Double = 0.05
    ) -> Result? {
        guard hopSeconds.isFinite, hopSeconds > 0,
              currentTotalOffset.isFinite,
              searchRadius.isFinite, searchRadius > 0,
              step.isFinite, step > 0,
              onsetEnvelope.count >= 20
        else { return nil }
        let searchRange = (currentTotalOffset - searchRadius)...(currentTotalOffset + searchRadius)
        let times = distinctSingingPointTimes(from: lyricTimes)
        guard times.count >= 2 else { return nil }

        let envelopeEnd = envelopeStartPlayback + Double(onsetEnvelope.count) * hopSeconds
        // Only lyrics that can fall inside the capture window for some lag in range.
        let usable = times.filter {
            $0 >= envelopeStartPlayback + searchRange.lowerBound - 0.5
                && $0 <= envelopeEnd + searchRange.upperBound + 0.5
        }
        guard usable.count >= 2 else { return nil }

        let envelopeMax = onsetEnvelope.max() ?? 0
        guard envelopeMax > 1e-6 else { return nil }

        let norm: [Float] = onsetEnvelope.map { $0 / envelopeMax }

        var bestOffset = 0.0
        var bestScore: Double = -Double.greatestFiniteMagnitude
        var bestCandidateIndex = 0
        var candidates: [(offset: Double, score: Double)] = []
        var scores: [Double] = []
        let candidateCapacity = Int((searchRange.upperBound - searchRange.lowerBound) / step) + 4
        scores.reserveCapacity(candidateCapacity)
        candidates.reserveCapacity(candidateCapacity)

        var candidate = searchRange.lowerBound
        while candidate <= searchRange.upperBound + 1e-9 {
            let scored = scoreOffset(
                offset: candidate,
                onset: norm,
                hopSeconds: hopSeconds,
                envelopeStartPlayback: envelopeStartPlayback,
                lyricTimes: usable
            )
            scores.append(scored.score)
            candidates.append((candidate, scored.score))
            if scored.score > bestScore {
                bestScore = scored.score
                bestOffset = candidate
                bestCandidateIndex = candidates.count - 1
            }
            candidate += step
        }

        let mean = scores.reduce(0, +) / Double(max(1, scores.count))
        guard bestScore > 1e-6 else { return nil }

        // The neighborhood lookup intentionally creates a short flat peak. Taking
        // the first equal candidate biases every estimate early by roughly 100 ms;
        // use the center of this one contiguous plateau instead.
        let plateauFloor = bestScore - max(1e-9, abs(bestScore) * 1e-6)
        var plateauLowerIndex = bestCandidateIndex
        var plateauUpperIndex = bestCandidateIndex
        while plateauLowerIndex > 0,
              candidates[plateauLowerIndex - 1].score >= plateauFloor
        {
            plateauLowerIndex -= 1
        }
        while plateauUpperIndex + 1 < candidates.count,
              candidates[plateauUpperIndex + 1].score >= plateauFloor
        {
            plateauUpperIndex += 1
        }
        bestOffset = (
            candidates[plateauLowerIndex].offset + candidates[plateauUpperIndex].offset
        ) / 2

        let peakRatio = bestScore / max(mean, 1e-9)
        // Smoothing and the +/-80 ms lookup neighborhood create one broad peak.
        // Ignore that peak's shoulders, but treat a separate near-equal peak as
        // ambiguous. Repeating beats/downbeats otherwise produce a stable, wrong
        // result that confirmation in a later capture cannot disprove.
        let samePeakRadius = max(0.25, 0.16 + hopSeconds * 2, step * 4)
        let independentSecondScore = candidates.lazy
            .filter { abs($0.offset - bestOffset) >= samePeakRadius }
            .map(\.score)
            .max() ?? 0
        let competingPeakRatio = max(0, independentSecondScore) / bestScore
        guard competingPeakRatio < 0.88 else { return nil }

        // A winner at (or very near) either bound may only be the visible shoulder
        // of a better peak outside the range. It must be re-run around that total
        // offset instead of being persisted as a bounded correction.
        let boundaryMargin = max(0.10, step * 2)
        guard bestOffset - searchRange.lowerBound > boundaryMargin,
              searchRange.upperBound - bestOffset > boundaryMargin
        else { return nil }

        let prominence = bestScore - max(0, independentSecondScore)
        let hits = hitCount(
            offset: bestOffset,
            onset: norm,
            hopSeconds: hopSeconds,
            envelopeStartPlayback: envelopeStartPlayback,
            lyricTimes: usable,
            threshold: 0.08
        )

        // Stricter confidence — prefer “no auto write” over a wrong ±seconds lock.
        let confFromRatio = min(1, max(0, (peakRatio - 1.15) / 1.3))
        let confFromProminence = min(1, max(0, prominence / max(bestScore, 1e-9)))
        let confFromHits = min(1, Double(hits) / 5.0)
        let confidence = confFromRatio * 0.45 + confFromProminence * 0.25 + confFromHits * 0.30

        let ok = confidence >= 0.40 && hits >= 3 && peakRatio >= 1.18
        guard ok else { return nil }

        let quantized = (bestOffset * 20).rounded() / 20
        if abs(quantized) < 0.08 {
            return Result(offset: 0, confidence: confidence, peakRatio: peakRatio, hits: hits)
        }
        return Result(offset: quantized, confidence: confidence, peakRatio: peakRatio, hits: hits)
    }

    /// Source-compatible entry point for callers that supplied the original
    /// absolute search range. New code should pass a center and radius instead.
    @available(*, deprecated, message: "Use currentTotalOffset and searchRadius")
    public static func bestOffset(
        onsetEnvelope: [Float],
        hopSeconds: Double,
        envelopeStartPlayback: TimeInterval,
        lyricTimes: [TimeInterval],
        searchRange: ClosedRange<Double>,
        step: Double = 0.05
    ) -> Result? {
        guard searchRange.lowerBound.isFinite,
              searchRange.upperBound.isFinite,
              searchRange.lowerBound < searchRange.upperBound
        else { return nil }
        let center = searchRange.lowerBound
            + (searchRange.upperBound - searchRange.lowerBound) / 2
        let radius = (searchRange.upperBound - searchRange.lowerBound) / 2
        return bestOffset(
            onsetEnvelope: onsetEnvelope,
            hopSeconds: hopSeconds,
            envelopeStartPlayback: envelopeStartPlayback,
            lyricTimes: lyricTimes,
            currentTotalOffset: center,
            searchRadius: radius,
            step: step
        )
    }

    /// How many non-empty lyric lines fall inside a future capture window.
    public static func lyricCount(
        inPlaybackWindow start: TimeInterval,
        duration: TimeInterval,
        lyricTimes: [TimeInterval]
    ) -> Int {
        let end = start + duration
        let inWindow = lyricTimes.filter {
            $0 >= start - 0.25 && $0 <= end + 0.25
        }
        return distinctSingingPointTimes(from: inWindow).count
    }

    // MARK: - Private

    private static func scoreOffset(
        offset: Double,
        onset: [Float],
        hopSeconds: Double,
        envelopeStartPlayback: TimeInterval,
        lyricTimes: [TimeInterval]
    ) -> (score: Double, inWindow: Int) {
        var score = 0.0
        var weightSum = 0.0
        var inWindow = 0
        // Wider neighborhood (~±80ms) absorbs LRC quantization + mic latency.
        let radius = max(1, Int((0.08 / hopSeconds).rounded()))

        for (i, lyricTime) in lyricTimes.enumerated() {
            // Vocal for line L expected near playback P = L - offset.
            let expectedPlayback = lyricTime - offset
            let rel = expectedPlayback - envelopeStartPlayback
            guard rel >= -0.05 else { continue }
            let idx = Int((rel / hopSeconds).rounded())
            guard onset.indices.contains(idx) else { continue }
            inWindow += 1
            let w = 1.0 + min(1.2, Double(i) * 0.04)
            let local = neighborhoodMax(onset, index: idx, radius: radius)
            score += Double(local) * w
            weightSum += w
        }
        guard weightSum > 0, inWindow >= 2 else { return (0, inWindow) }
        return (score / weightSum, inWindow)
    }

    private static func hitCount(
        offset: Double,
        onset: [Float],
        hopSeconds: Double,
        envelopeStartPlayback: TimeInterval,
        lyricTimes: [TimeInterval],
        threshold: Float
    ) -> Int {
        let radius = max(1, Int((0.08 / hopSeconds).rounded()))
        var hits = 0
        for lyricTime in lyricTimes {
            let expectedPlayback = lyricTime - offset
            let rel = expectedPlayback - envelopeStartPlayback
            guard rel >= -0.05 else { continue }
            let idx = Int((rel / hopSeconds).rounded())
            guard onset.indices.contains(idx) else { continue }
            if neighborhoodMax(onset, index: idx, radius: radius) >= threshold {
                hits += 1
            }
        }
        return hits
    }

    private static func neighborhoodMax(_ values: [Float], index: Int, radius: Int) -> Float {
        let lo = max(0, index - radius)
        let hi = min(values.count - 1, index + radius)
        var m: Float = 0
        for i in lo...hi {
            m = max(m, values[i])
        }
        return m
    }
}
