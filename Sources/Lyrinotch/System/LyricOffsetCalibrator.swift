import AVFoundation
import Darwin
import Foundation
import LyrinotchCore

/// Thread-safe hop energy collector shared with the audio render callback.
private final class AudioEnergyBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var energy: [Float]
    private var energyCount = 0
    private var overflowed = false
    private var didReceiveFirstBuffer = false
    private var firstHostTime: UInt64?
    private var previousSample: Float?
    private var hopSumSquares: Float = 0
    private var hopSampleCount = 0

    init(capacity: Int) {
        // Allocate fixed storage before installing the real-time tap. The audio
        // callback never grows an Array; an unexpectedly long capture is marked
        // invalid instead of allocating on the render thread.
        energy = [Float](repeating: 0, count: max(1, capacity))
    }

    /// Consumes AVAudioEngine channel pointers in-place. No temporary mono array
    /// or `removeFirst` shifting occurs on the real-time render callback.
    func appendBrightness(
        channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        isInterleaved: Bool,
        stride: Int,
        frames: Int,
        hop: Int,
        hostTime: UInt64?
    ) {
        guard hop > 0, channelCount > 0, stride > 0, frames > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        if !didReceiveFirstBuffer {
            didReceiveFirstBuffer = true
            // If the first packet has no host timestamp, use the playback anchor
            // fallback for the whole capture. Treating a later packet as time zero
            // would introduce one full callback of false delay.
            firstHostTime = hostTime
        }

        var previous = previousSample
        for index in 0..<frames {
            var mixedSample: Float = 0
            if isInterleaved {
                let frameStart = index * stride
                for channel in 0..<channelCount {
                    mixedSample += channels[0][frameStart + channel]
                }
            } else {
                let sampleIndex = index * stride
                for channel in 0..<channelCount {
                    mixedSample += channels[channel][sampleIndex]
                }
            }
            let sample = mixedSample / Float(channelCount)
            let delta = previous.map { abs(sample - $0) } ?? 0
            previous = sample
            hopSumSquares += delta * delta
            hopSampleCount += 1
            if hopSampleCount == hop {
                if energyCount < energy.count {
                    energy[energyCount] = sqrtf(hopSumSquares / Float(hop))
                    energyCount += 1
                } else {
                    overflowed = true
                }
                hopSumSquares = 0
                hopSampleCount = 0
            }
        }
        previousSample = previous
    }

    func snapshot() -> (energy: [Float], firstHostTime: UInt64?, overflowed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (Array(energy.prefix(energyCount)), firstHostTime, overflowed)
    }
}

/// Keeps the short microphone capture tied to one continuous player timeline.
/// A seek during capture changes the apparent lyric offset, so that sample must
/// be discarded instead of being saved as a constant per-track correction.
struct LyricCalibrationPlaybackContinuity {
    private let anchorPosition: TimeInterval
    private let anchorUptime: TimeInterval
    private var previousPosition: TimeInterval
    private var previousUptime: TimeInterval
    private let maximumStepError: TimeInterval
    private let maximumAccumulatedError: TimeInterval

    init(
        position: TimeInterval,
        uptime: TimeInterval,
        maximumStepError: TimeInterval = 0.65,
        maximumAccumulatedError: TimeInterval = 0.55
    ) {
        anchorPosition = position
        anchorUptime = uptime
        previousPosition = position
        previousUptime = uptime
        self.maximumStepError = maximumStepError
        self.maximumAccumulatedError = maximumAccumulatedError
    }

    /// Returns false when the player position no longer advances with elapsed
    /// monotonic time. The accumulated check also catches players that smooth a
    /// seek over several smaller clock corrections.
    mutating func observe(position: TimeInterval, uptime: TimeInterval) -> Bool {
        guard position.isFinite, uptime.isFinite,
              uptime >= previousUptime, uptime >= anchorUptime
        else { return false }

        let stepAdvance = position - previousPosition
        let stepElapsed = uptime - previousUptime
        let accumulatedAdvance = position - anchorPosition
        let accumulatedElapsed = uptime - anchorUptime
        previousPosition = position
        previousUptime = uptime

        return abs(stepAdvance - stepElapsed) <= maximumStepError
            && abs(accumulatedAdvance - accumulatedElapsed) <= maximumAccumulatedError
    }
}

/// Pure timeline calculations kept separate from microphone I/O so their sign
/// convention and search-window behavior can be regression tested.
enum LyricCalibrationTimeline {
    static func adjustedPosition(
        playbackPosition: TimeInterval,
        currentTotalOffset: TimeInterval
    ) -> TimeInterval {
        playbackPosition + currentTotalOffset
    }

    static func focusedLyricTimes(
        _ lyricTimes: [TimeInterval],
        envelopeStartPlayback: TimeInterval,
        envelopeDuration: TimeInterval,
        currentTotalOffset: TimeInterval,
        searchRadius: TimeInterval = LyricOffsetAligner.micSearchRadius,
        padding: TimeInterval = 0.5
    ) -> [TimeInterval] {
        let envelopeEnd = envelopeStartPlayback + max(0, envelopeDuration)
        let lowerBound = envelopeStartPlayback + currentTotalOffset - searchRadius - padding
        let upperBound = envelopeEnd + currentTotalOffset + searchRadius + padding
        let inWindow = lyricTimes.filter { $0 >= lowerBound && $0 <= upperBound }
        return LyricOffsetAligner.distinctSingingPointTimes(from: inWindow)
    }

    static func bestOffset(
        onsetEnvelope: [Float],
        hopSeconds: TimeInterval,
        envelopeStartPlayback: TimeInterval,
        lyricTimes: [TimeInterval],
        currentTotalOffset: TimeInterval,
        searchRadius: TimeInterval = LyricOffsetAligner.micSearchRadius
    ) -> LyricOffsetAligner.Result? {
        let focusedTimes = focusedLyricTimes(
            lyricTimes,
            envelopeStartPlayback: envelopeStartPlayback,
            envelopeDuration: Double(onsetEnvelope.count) * hopSeconds,
            currentTotalOffset: currentTotalOffset,
            searchRadius: searchRadius
        )
        let timesForMatch = focusedTimes.count >= 3 ? focusedTimes : lyricTimes
        return LyricOffsetAligner.bestOffset(
            onsetEnvelope: onsetEnvelope,
            hopSeconds: hopSeconds,
            envelopeStartPlayback: envelopeStartPlayback,
            lyricTimes: timesForMatch,
            currentTotalOffset: currentTotalOffset,
            searchRadius: searchRadius
        )
    }
}

/// Listens on the microphone for a short window and aligns LRC onsets with audio onsets.
///
/// Works best when Spotify/Music plays through **speakers** (mic must hear the mix).
/// Headphones without bleed usually yield low confidence → skipped (not a hard failure).
@MainActor
final class LyricOffsetCalibrator: NSObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case waitingForLyrics
        case listening(progress: Double)
        case succeeded(offset: Double, confidence: Double)
        case failed(String)
        case skipped(String)
    }

    private(set) var state: State = .idle
    var onStateChange: ((State) -> Void)?

    private let audioEngine = AVAudioEngine()
    /// Replaced for every capture so an in-flight callback from a removed tap
    /// can only mutate its retired collector, never the next track's samples.
    private var energyBuffer: AudioEnergyBuffer?
    private var hopSeconds: Double = 0.02
    private var envelopeStartPlayback: TimeInterval = 0
    private var playbackAnchorPosition: TimeInterval = 0
    private var playbackAnchorHostTime: UInt64 = 0
    private var currentTotalOffset: TimeInterval = 0
    private var playbackContinuity: LyricCalibrationPlaybackContinuity?
    private var lyricTimes: [TimeInterval] = []
    private var positionProvider: (() -> TimeInterval)?
    private var isPlayingProvider: (() -> Bool)?
    private var stopTask: Task<Void, Never>?
    private var resetStateTask: Task<Void, Never>?
    private var targetDuration: TimeInterval = 14
    private var samplesPerHop = 0
    /// Invalidates delayed microphone-permission callbacks from an older track.
    private var generation: UInt64 = 0

    func stop() {
        generation &+= 1
        stopTask?.cancel()
        stopTask = nil
        resetStateTask?.cancel()
        resetStateTask = nil
        tearDownEngine()
        energyBuffer = nil
        switch state {
        case .listening, .waitingForLyrics, .requestingPermission:
            state = .idle
            onStateChange?(state)
        default:
            break
        }
    }

    /// Begin a calibration pass (may wait until enough lyric lines enter the window).
    func start(
        lyricTimes: [TimeInterval],
        position: @escaping () -> TimeInterval,
        isPlaying: @escaping () -> Bool,
        duration: TimeInterval = 14,
        currentTotalOffset: TimeInterval = 0
    ) {
        stop()
        let startGeneration = generation
        let times = LyricOffsetAligner.distinctSingingPointTimes(from: lyricTimes)
        guard times.count >= 3 else {
            finish(.skipped(L10n.t("offset_cal.too_few_timed_lines", times.count)))
            return
        }
        guard isPlaying() else {
            finish(.skipped(L10n.t("offset_cal.skip_paused")))
            return
        }
        guard currentTotalOffset.isFinite else {
            finish(.skipped(L10n.t("offset_cal.skip_low_confidence")))
            return
        }

        self.lyricTimes = times
        self.positionProvider = position
        self.isPlayingProvider = isPlaying
        self.targetDuration = min(18, max(10, duration))
        self.currentTotalOffset = currentTotalOffset

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            waitThenListen()
        case .notDetermined:
            state = .requestingPermission
            onStateChange?(state)
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self,
                          self.generation == startGeneration,
                          self.state == .requestingPermission
                    else { return }
                    if granted {
                        self.waitThenListen()
                    } else {
                        self.finish(.failed(L10n.t("offset_cal.mic_denied")))
                    }
                }
            }
        default:
            finish(.failed(L10n.t("offset_cal.mic_denied")))
        }
    }

    // MARK: - Private

    private func waitThenListen() {
        state = .waitingForLyrics
        onStateChange?(state)

        stopTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<90 {
                guard !Task.isCancelled else { return }
                guard self.isPlayingProvider?() != false else {
                    self.finish(.skipped(L10n.t("offset_cal.skip_paused")))
                    return
                }
                let pos = self.positionProvider?() ?? 0
                let count = LyricOffsetAligner.lyricCount(
                    inPlaybackWindow: LyricCalibrationTimeline.adjustedPosition(
                        playbackPosition: pos,
                        currentTotalOffset: self.currentTotalOffset
                    ),
                    duration: self.targetDuration,
                    lyricTimes: self.lyricTimes
                )
                if count >= 3 {
                    self.beginListening()
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            self.finish(.skipped(L10n.t("offset_cal.sparse_window")))
        }
    }

    private func beginListening() {
        stopTask?.cancel()
        stopTask = nil

        let input = audioEngine.inputNode
        audioEngine.prepare()
        // A tap on AVAudioEngine's input node observes its output bus. Apple's
        // documented input-node tap pattern therefore uses outputFormat.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            finish(.failed(L10n.t("offset_cal.audio_unavailable")))
            return
        }

        hopSeconds = 0.02
        samplesPerHop = max(64, Int((format.sampleRate * hopSeconds).rounded()))
        hopSeconds = Double(samplesPerHop) / format.sampleRate

        let hop = samplesPerHop
        let capacity = max(
            1,
            Int(ceil((targetDuration + 2) / hopSeconds))
        )
        let collector = AudioEnergyBuffer(capacity: capacity)
        energyBuffer = collector
        input.removeTap(onBus: 0)
        // AVAudioEngine documents tap buffers in the 100–400 ms range. Hop
        // accumulation remains 20 ms, independent of this callback cadence.
        let tapFrames = max(hop * 2, Int((format.sampleRate * 0.1).rounded()))
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(tapFrames), format: format) {
            pcm, when in
            guard let channels = pcm.floatChannelData else { return }
            let frames = Int(pcm.frameLength)
            guard frames > 0 else { return }
            collector.appendBrightness(
                channels: channels,
                channelCount: Int(pcm.format.channelCount),
                isInterleaved: pcm.format.isInterleaved,
                stride: pcm.stride,
                frames: frames,
                hop: hop,
                hostTime: when.isHostTimeValid ? when.hostTime : nil
            )
        }

        do {
            try audioEngine.start()
        } catch {
            finish(.failed(L10n.t("offset_cal.audio_unavailable")))
            return
        }

        // Anchor the player clock after engine startup. The first buffer's host
        // timestamp below compensates for any remaining input-pipeline latency.
        playbackAnchorPosition = positionProvider?() ?? 0
        playbackAnchorHostTime = mach_absolute_time()
        playbackContinuity = LyricCalibrationPlaybackContinuity(
            position: playbackAnchorPosition,
            uptime: ProcessInfo.processInfo.systemUptime
        )

        state = .listening(progress: 0)
        onStateChange?(state)

        stopTask = Task { [weak self] in
            guard let self else { return }
            let steps = Int(self.targetDuration * 10)
            for i in 0..<steps {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                // Route/sample-rate changes stop AVAudioEngine. Never analyze a
                // truncated capture as though it represented the full window.
                guard self.audioEngine.isRunning else {
                    self.finish(.skipped(L10n.t("offset_cal.audio_unavailable")))
                    return
                }
                if self.isPlayingProvider?() == false {
                    self.finish(.skipped(L10n.t("offset_cal.skip_paused")))
                    return
                }
                guard let position = self.positionProvider?() else {
                    self.finish(.skipped(L10n.t("offset_cal.skip_low_confidence")))
                    return
                }
                if var continuity = self.playbackContinuity {
                    let isContinuous = continuity.observe(
                        position: position,
                        uptime: ProcessInfo.processInfo.systemUptime
                    )
                    self.playbackContinuity = continuity
                    guard isContinuous else {
                        self.finish(.skipped(L10n.t("offset_cal.skip_low_confidence")))
                        return
                    }
                }
                let p = min(1, Double(i + 1) / Double(steps))
                self.state = .listening(progress: p)
                self.onStateChange?(self.state)
            }
            self.completeAnalysis()
        }
    }

    private func completeAnalysis() {
        guard let collector = energyBuffer else {
            finish(.failed(L10n.t("offset_cal.audio_unavailable")))
            return
        }
        tearDownEngine()

        let capture = collector.snapshot()
        energyBuffer = nil
        guard !capture.overflowed else {
            finish(.skipped(L10n.t("offset_cal.skip_low_confidence")))
            return
        }
        let energy = capture.energy
        envelopeStartPlayback = playbackAnchorPosition
        if let firstHostTime = capture.firstHostTime, playbackAnchorHostTime > 0 {
            let firstSeconds = AVAudioTime.seconds(forHostTime: firstHostTime)
            let anchorSeconds = AVAudioTime.seconds(forHostTime: playbackAnchorHostTime)
            let delta = firstSeconds - anchorSeconds
            if delta.isFinite, abs(delta) < 2 {
                envelopeStartPlayback = max(0, playbackAnchorPosition + delta)
            }
        }
        let peak = energy.max() ?? 0
        if peak < 0.000_35 {
            finish(.skipped(L10n.t("offset_cal.skip_quiet")))
            return
        }

        let onset = LyricOffsetAligner.onsetStrength(fromEnergy: energy)
        guard let result = LyricCalibrationTimeline.bestOffset(
            onsetEnvelope: onset,
            hopSeconds: hopSeconds,
            envelopeStartPlayback: envelopeStartPlayback,
            lyricTimes: lyricTimes,
            currentTotalOffset: currentTotalOffset
        ) else {
            finish(.skipped(L10n.t("offset_cal.skip_low_confidence")))
            return
        }

        finish(.succeeded(offset: result.offset, confidence: max(result.confidence, 0.25)))
    }

    private func tearDownEngine() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        } else {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    private func finish(_ newState: State) {
        stopTask?.cancel()
        stopTask = nil
        tearDownEngine()
        energyBuffer = nil
        state = newState
        onStateChange?(state)
        switch newState {
        case .succeeded, .failed, .skipped:
            resetStateTask?.cancel()
            let finishGeneration = generation
            resetStateTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self,
                      !Task.isCancelled,
                      self.generation == finishGeneration,
                      self.state == newState
                else { return }
                self.state = .idle
                self.resetStateTask = nil
                self.onStateChange?(self.state)
            }
        default:
            break
        }
    }
}
