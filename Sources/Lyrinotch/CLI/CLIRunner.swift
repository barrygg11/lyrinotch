import Foundation
import LyrinotchCore

/// Headless Phase 1/2 style runner (`--cli` / `--once`).
enum CLIRunner {
    static func runSync(arguments: [String]) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await run(arguments: arguments)
            semaphore.signal()
        }
        semaphore.wait()
    }

    static func run(arguments: [String]) async {
        let once = arguments.contains("--once")
        let intervalMs = parseIntervalMs(from: arguments) ?? 1000

        print("Lyrinotch — Spotify / Apple Music lyrics near the MacBook notch")
        print("Mode: CLI (Phase 1–2)")
        print(once ? "Snapshot: --once" : "Poll every \(intervalMs)ms  (Ctrl+C to quit)")
        print("")

        let nowPlaying = NowPlayingService()
        let lyricsService = LyricsService()

        var lastTrackKey: String?
        var lastAvailability: NowPlayingAvailability?
        var lyrics = LyricsSnapshot.skipped
        var lastLyricPrint: String?

        repeat {
            let snap = await nowPlaying.snapshot()
            let trackKey = trackCacheKey(snap)

            let trackChanged =
                trackKey != lastTrackKey
                || snap.availability != lastAvailability

            if trackChanged {
                if lastTrackKey != nil {
                    print("")
                }
                printStatusHeader(snap)
                lastTrackKey = trackKey
                lastAvailability = snap.availability
                lastLyricPrint = nil

                if snap.availability == .ready {
                    lyrics = await lyricsService.snapshot(for: snap.track)
                    printLyricsHeader(lyrics)
                } else {
                    lyrics = .skipped
                }
            }

            printLiveLine(snap: snap, lyrics: lyrics, lastLyricPrint: &lastLyricPrint)
            fflush(stdout)

            if once {
                if snap.availability == .ready {
                    printSyncedPreview(
                        lyrics: lyrics,
                        position: snap.track.position,
                        duration: snap.track.duration
                    )
                }
                break
            }

            try? await Task.sleep(for: .milliseconds(intervalMs))
        } while true

        print("")
    }

    // MARK: - Formatting

    private static func printStatusHeader(_ snap: NowPlayingSnapshot) {
        switch snap.availability {
        case .ready:
            let track = snap.track
            let state = track.isPlaying ? "playing" : "paused"
            let album = track.album.map { " · \(sanitizeTerminalText($0))" } ?? ""
            let player = snap.source?.displayName ?? "player"
            print("♪ \(sanitizeTerminalText(track.displayTitle))\(album)")
            print("  via: \(sanitizeTerminalText(player))  state: \(state)  id: \(sanitizeTerminalText(track.id ?? "—"))")
        case .playerNotRunning:
            print("○ No music player running (Spotify / Apple Music)")
        case .noTrack:
            print("○ Player idle (no track)")
        case .error:
            print("✗ Failed to read now playing")
            if let detail = snap.detail {
                print("  \(sanitizeTerminalText(detail))")
            }
        }
    }

    private static func printLyricsHeader(_ lyrics: LyricsSnapshot) {
        switch lyrics.availability {
        case .synced:
            print("  lyrics: synced (\(lyrics.lines.count) lines, \(sanitizeTerminalText(lyrics.source ?? "?")))")
        case .plain:
            print("  lyrics: plain (estimated timeline, \(lyrics.plainLines.count) lines)")
        case .instrumental:
            print("  lyrics: instrumental")
        case .notFound:
            print("  lyrics: not found")
        case .error:
            print("  lyrics: error — \(sanitizeTerminalText(lyrics.detail ?? "unknown"))")
        case .skipped:
            print("  lyrics: skipped")
        }
    }

    private static func printLiveLine(
        snap: NowPlayingSnapshot,
        lyrics: LyricsSnapshot,
        lastLyricPrint: inout String?
    ) {
        guard snap.availability == .ready else {
            let detail = sanitizeTerminalText(snap.detail ?? snap.availability.rawValue)
            print("\r  … \(detail)                                        ", terminator: "")
            return
        }

        let track = snap.track
        let pos = formatTime(track.position)
        let dur = formatTime(track.duration)
        let glyph = track.isPlaying ? "▶" : "⏸"
        let lyricText = lyrics.activeText(at: track.position, duration: track.duration) ?? fallbackLyric(lyrics)

        if (lyrics.availability == .synced || lyrics.availability == .plain),
           let active = lyrics.activeText(at: track.position, duration: track.duration),
           active != lastLyricPrint {
            if lastLyricPrint != nil { print("") }
            let safeActive = sanitizeTerminalText(active)
            print("  ♫ \(safeActive)")
            lastLyricPrint = active
        }

        print("\r  \(glyph)  \(pos)/\(dur)  \(truncate(sanitizeTerminalText(lyricText), max: 48))                    ", terminator: "")
    }

    private static func fallbackLyric(_ lyrics: LyricsSnapshot) -> String {
        switch lyrics.availability {
        case .synced: return "…"
        case .plain: return "(plain lyrics)"
        case .instrumental: return "(instrumental)"
        case .notFound: return "(no lyrics)"
        case .error: return "(lyrics error)"
        case .skipped: return ""
        }
    }

    private static func printSyncedPreview(lyrics: LyricsSnapshot, position: TimeInterval?, duration: TimeInterval? = nil) {
        let lines = lyrics.displayLines(duration: duration)
        guard !lines.isEmpty else { return }
        print("")
        print("  — lyrics around playhead —")
        let pos = position ?? 0
        let idx = LyricLine.activeIndex(in: lines, at: pos) ?? 0
        let start = max(0, idx - 1)
        let end = min(lines.count - 1, idx + 2)
        for i in start...end {
            let mark = (i == idx) ? ">" : " "
            let line = lines[i]
            print("  \(mark) [\(line.timeString)] \(sanitizeTerminalText(line.text))")
        }
    }

    private static func trackCacheKey(_ snap: NowPlayingSnapshot) -> String {
        switch snap.availability {
        case .ready:
            return "ready|\(TrackIdentity(track: snap.track, source: snap.source).storageKey)"
        case .playerNotRunning, .noTrack, .error:
            return snap.availability.rawValue + "|" + (snap.detail ?? "")
        }
    }

    private static func formatTime(_ seconds: TimeInterval?) -> String {
        guard let seconds,
              let safeSeconds = LyricsInputLimits.validDuration(seconds)
        else { return "--:--" }
        let total = Int(safeSeconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        let end = text.index(text.startIndex, offsetBy: max - 1)
        return String(text[..<end]) + "…"
    }

    static func sanitizeTerminalText(_ text: String) -> String {
        text.unicodeScalars.reduce(into: String()) { result, scalar in
            let value = scalar.value
            if value == 0x09 || value == 0x0A {
                result.unicodeScalars.append(scalar)
            } else if value < 0x20 || (0x7F...0x9F).contains(value) {
                result += String(format: "\\u{%02X}", value)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
    }

    private static func parseIntervalMs(from args: [String]) -> Int? {
        guard let idx = args.firstIndex(of: "--interval-ms"),
              args.index(after: idx) < args.endIndex,
              let value = Int(args[args.index(after: idx)]),
              value >= 200
        else { return nil }
        return value
    }
}
