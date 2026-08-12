import Foundation

/// Sends basic transport commands to Spotify or Music.app via AppleScript.
public actor PlaybackService {
    public enum Command: String, Sendable {
        case playPause
        case next
        case previous
    }

    public enum PlaybackError: Error, Equatable, Sendable, LocalizedError {
        case playerNotRunning
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .playerNotRunning:
                return "沒有正在執行的音樂播放器"
            case .failed(let message):
                return message
            }
        }
    }

    private let executor: any AppleScriptExecuting

    public init(executor: any AppleScriptExecuting = ProcessAppleScriptExecutor()) {
        self.executor = executor
    }

    public func perform(_ command: Command, source: MusicPlayerSource) async throws {
        let script: String
        switch (source, command) {
        case (.spotify, .playPause):
            script = SpotifyAppleScript.playPauseScript
        case (.spotify, .next):
            script = SpotifyAppleScript.nextTrackScript
        case (.spotify, .previous):
            script = SpotifyAppleScript.previousTrackScript
        case (.appleMusic, .playPause):
            script = MusicAppleScript.playPauseScript
        case (.appleMusic, .next):
            script = MusicAppleScript.nextTrackScript
        case (.appleMusic, .previous):
            script = MusicAppleScript.previousTrackScript
        }
        try await run(script)
    }

    /// Jump playback to `seconds` (clamped ≥ 0).
    public func seek(to seconds: TimeInterval, source: MusicPlayerSource) async throws {
        let script: String
        switch source {
        case .spotify:
            script = SpotifyAppleScript.seekScript(seconds: seconds)
        case .appleMusic:
            script = MusicAppleScript.seekScript(seconds: seconds)
        }
        try await run(script)
    }

    private func run(_ script: String) async throws {
        do {
            let raw = try await executor.run(script: script)
            if raw == "NOT_RUNNING" {
                throw PlaybackError.playerNotRunning
            }
            if raw.hasPrefix("ERROR") {
                throw PlaybackError.failed(raw)
            }
        } catch let error as PlaybackError {
            throw error
        } catch {
            throw PlaybackError.failed(error.localizedDescription)
        }
    }
}

/// Historical name — maps onto unified `PlaybackService` for Spotify-only tests.
public actor SpotifyPlaybackService {
    public typealias Command = PlaybackService.Command
    public typealias PlaybackError = PlaybackService.PlaybackError

    private let inner: PlaybackService

    public init(executor: any SpotifyScriptExecuting = ProcessSpotifyScriptExecutor()) {
        self.inner = PlaybackService(executor: executor)
    }

    public func playPause() async throws {
        try await inner.perform(.playPause, source: .spotify)
    }

    public func nextTrack() async throws {
        try await inner.perform(.next, source: .spotify)
    }

    public func previousTrack() async throws {
        try await inner.perform(.previous, source: .spotify)
    }

    public func perform(_ command: Command) async throws {
        try await inner.perform(command, source: .spotify)
    }
}
