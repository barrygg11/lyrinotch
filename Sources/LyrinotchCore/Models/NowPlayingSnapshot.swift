import Foundation

/// High-level availability of a now-playing read (Spotify and/or Apple Music).
public enum NowPlayingAvailability: String, Sendable, Equatable {
    /// A supported player is running and a track payload was parsed.
    case ready
    /// No supported player (Spotify / Music) is running.
    case playerNotRunning
    /// A player is running but nothing is loaded / stopped.
    case noTrack
    /// osascript failed, Automation denied, or payload was unreadable.
    case error

    /// Historical name used before Apple Music support.
    public static let spotifyNotRunning = NowPlayingAvailability.playerNotRunning
}

/// One poll result from `NowPlayingService`.
public struct NowPlayingSnapshot: Sendable, Equatable {
    public var availability: NowPlayingAvailability
    public var track: Track
    /// Optional human-readable detail (error text, raw state, etc.).
    public var detail: String?
    /// Which desktop player produced this snapshot (when known).
    public var source: MusicPlayerSource? {
        didSet {
            if availability == .ready {
                track.source = source
            }
        }
    }

    public init(
        availability: NowPlayingAvailability,
        track: Track = .empty,
        detail: String? = nil,
        source: MusicPlayerSource? = nil
    ) {
        let resolvedSource = source ?? track.source
        var resolvedTrack = track
        if availability == .ready {
            resolvedTrack.source = resolvedSource
        }
        self.availability = availability
        self.track = resolvedTrack
        self.detail = detail
        self.source = resolvedSource
    }

    public var trackIdentity: TrackIdentity? {
        guard availability == .ready else { return nil }
        return TrackIdentity(track: track, source: source)
    }

    public static let playerNotRunning = NowPlayingSnapshot(
        availability: .playerNotRunning,
        track: .empty,
        detail: "No music player is running"
    )

    /// Historical alias.
    public static let spotifyNotRunning = playerNotRunning

    public static let noTrack = NowPlayingSnapshot(
        availability: .noTrack,
        track: .empty,
        detail: "No track loaded"
    )
}

/// Picks the best snapshot when both Spotify and Music are queried.
public enum NowPlayingSelector {
    /// Prefer a **playing** track; else any ready track; else map idle states.
    public static func pick(
        spotify: NowPlayingSnapshot,
        music: NowPlayingSnapshot,
        preferredSource: MusicPlayerSource? = nil
    ) -> NowPlayingSnapshot {
        var spotify = spotify
        if spotify.source == nil, spotify.availability != .playerNotRunning {
            spotify.source = .spotify
        }
        var music = music
        if music.source == nil, music.availability != .playerNotRunning {
            music.source = .appleMusic
        }

        let ready = [spotify, music].filter { $0.availability == .ready }
        let playing = ready.filter { $0.track.isPlaying }
        if let preferredSource,
           let preferred = playing.first(where: { $0.source == preferredSource })
        {
            return preferred
        }
        if let playing = playing.first {
            return playing
        }
        if let preferredSource,
           let preferred = ready.first(where: { $0.source == preferredSource })
        {
            return preferred
        }
        if let paused = ready.first {
            return paused
        }

        // Neither ready — prefer a concrete error if one side failed hard.
        if spotify.availability == .error { return spotify }
        if music.availability == .error { return music }

        if spotify.availability == .noTrack || music.availability == .noTrack {
            return .noTrack
        }

        return .playerNotRunning
    }
}
