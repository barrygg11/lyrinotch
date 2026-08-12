import Foundation
import OSLog
import LyrinotchCore

/// Privacy-safe, bounded local diagnostics. It intentionally accepts only
/// operational metadata—never track titles, artists, lyric text, or audio.
final class AppDiagnostics: @unchecked Sendable {
    static let shared = AppDiagnostics()

    private struct Event: Sendable {
        var date: Date
        var category: String
        var detail: String
    }

    private let lock = NSLock()
    private let capacity: Int
    private var events: [Event] = []
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.lyrinotch.Lyrinotch",
        category: "diagnostics"
    )

    init(capacity: Int = 80) {
        self.capacity = max(1, capacity)
    }

    func recordPlayback(
        availability: NowPlayingAvailability,
        source: MusicPlayerSource?,
        latencyMilliseconds: Int
    ) {
        record(
            category: "playback",
            detail: "availability=\(availability.rawValue) source=\(source?.rawValue ?? "none") latency_ms=\(max(0, latencyMilliseconds))"
        )
    }

    func recordLyrics(
        availability: LyricsAvailability,
        source: String?,
        lineCount: Int,
        latencyMilliseconds: Int
    ) {
        let provider = Self.safeProviderLabel(source)
        record(
            category: "lyrics",
            detail: "availability=\(availability.rawValue) provider=\(provider) lines=\(max(0, lineCount)) latency_ms=\(max(0, latencyMilliseconds))"
        )
    }

    func recordCalibration(outcome: String, confidence: Double? = nil) {
        let normalizedOutcome = outcome
            .lowercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        let confidenceText = confidence.map {
            " confidence=\(Int((min(1, max(0, $0)) * 100).rounded()))"
        } ?? ""
        record(
            category: "calibration",
            detail: "outcome=\(normalizedOutcome.isEmpty ? "unknown" : normalizedOutcome)\(confidenceText)"
        )
    }

    var recentEventCount: Int {
        lock.withLock { events.count }
    }

    func recentText(limit: Int = 30) -> String {
        let snapshot = lock.withLock { Array(events.suffix(max(0, limit))) }
        guard !snapshot.isEmpty else { return "Recent events: none" }
        let formatter = ISO8601DateFormatter()
        let lines = snapshot.map {
            "\(formatter.string(from: $0.date)) [\($0.category)] \($0.detail)"
        }
        return (["Recent events (privacy-safe, local):"] + lines).joined(separator: "\n")
    }

    private func record(category: String, detail: String) {
        let event = Event(date: Date(), category: category, detail: detail)
        lock.withLock {
            events.append(event)
            if events.count > capacity {
                events.removeFirst(events.count - capacity)
            }
        }
        logger.info("\(category, privacy: .public) \(detail, privacy: .public)")
    }

    private static func safeProviderLabel(_ raw: String?) -> String {
        guard let raw else { return "none" }
        // Provider is deliberately allow-listed instead of merely sanitized:
        // a malformed/custom snapshot must never smuggle a song title or lyric
        // fragment into the diagnostics export.
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "lrclib": return "lrclib"
        case "netease": return "netease"
        case "lyrics.ovh": return "lyrics.ovh"
        case "apple-music": return "apple-music"
        case "composite": return "composite"
        case "local-lrc": return "local-lrc"
        case "manual-tap": return "manual-tap"
        default: return "unknown"
        }
    }
}
