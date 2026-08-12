import Foundation

/// Individual lyrics providers.
public enum LyricsSourceKind: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    /// Community synced/plain library (default).
    case lrclib
    /// Music.app embedded lyrics (`lyrics of current track`).
    case appleMusic
    /// NetEase Cloud Music unofficial lyric API (strong CJK / J-pop coverage).
    case netEase
    /// lyrics.ovh free plain-text API.
    case lyricsOvh

    public var id: String { rawValue }

    public var displayNameKey: String {
        switch self {
        case .lrclib: return "lyrics_source.lrclib"
        case .appleMusic: return "lyrics_source.apple_music"
        case .netEase: return "lyrics_source.netease"
        case .lyricsOvh: return "lyrics_source.lyrics_ovh"
        }
    }
}

/// Ordered multi-source strategy shown in Settings.
public enum LyricsSourcePreference: String, Codable, Sendable, CaseIterable, Equatable {
    /// Choose providers from player source, metadata script, and result quality.
    case smartAutomatic
    /// LRCLIB only.
    case lrclibOnly
    /// Music.app first, then online fallbacks (includes NetEase / ovh).
    case appleMusicThenLRCLIB
    /// LRCLIB first, then other online + Music.
    case lrclibThenAppleMusic
    /// NetEase first (good for CJK), then LRCLIB, lyrics.ovh, Music.
    case netEaseFirst
    /// Try online sources broadly: LRCLIB → NetEase → lyrics.ovh → Music.
    case allOnline
    /// Maximum coverage: Music → LRCLIB → NetEase → lyrics.ovh.
    case maximumCoverage

    public var displayNameKey: String {
        switch self {
        case .smartAutomatic: return "lyrics_source.pref_smart"
        case .lrclibOnly: return "lyrics_source.pref_lrclib_only"
        case .appleMusicThenLRCLIB: return "lyrics_source.pref_am_first"
        case .lrclibThenAppleMusic: return "lyrics_source.pref_lrclib_first"
        case .netEaseFirst: return "lyrics_source.pref_netease_first"
        case .allOnline: return "lyrics_source.pref_all_online"
        case .maximumCoverage: return "lyrics_source.pref_maximum"
        }
    }

    /// Short, non-duplicated set exposed in Settings. Legacy cases remain decodable.
    public static let settingsCases: [LyricsSourcePreference] = [
        .smartAutomatic,
        .lrclibOnly,
        .netEaseFirst,
        .maximumCoverage
    ]

    /// Collapse the duplicated pre-1.0.9 strategies into the new smart mode.
    public var normalizedForSettings: LyricsSourcePreference {
        switch self {
        case .appleMusicThenLRCLIB, .lrclibThenAppleMusic, .allOnline:
            return .smartAutomatic
        default:
            return self
        }
    }

    /// Providers to try, in order.
    ///
    /// Note: “Music → LRCLIB” / “LRCLIB → Music” still fall through to NetEase & lyrics.ovh
    /// so CJK TV-theme tracks are not stuck when LRCLIB has zero hits.
    public var pipeline: [LyricsSourceKind] {
        switch self {
        case .smartAutomatic:
            return [.lrclib, .netEase, .lyricsOvh, .appleMusic]
        case .lrclibOnly:
            return [.lrclib]
        case .appleMusicThenLRCLIB:
            return [.appleMusic, .lrclib, .netEase, .lyricsOvh]
        case .lrclibThenAppleMusic:
            return [.lrclib, .netEase, .lyricsOvh, .appleMusic]
        case .netEaseFirst:
            return [.netEase, .lrclib, .lyricsOvh, .appleMusic]
        case .allOnline:
            return [.lrclib, .netEase, .lyricsOvh, .appleMusic]
        case .maximumCoverage:
            return [.appleMusic, .lrclib, .netEase, .lyricsOvh]
        }
    }

    /// Provider order for one track. Smart mode avoids irrelevant sources early,
    /// while the fetcher still compares all usable results by quality.
    public func pipeline(
        for track: Track,
        playerSource: MusicPlayerSource?
    ) -> [LyricsSourceKind] {
        guard self == .smartAutomatic else { return pipeline }

        let metadata = "\(track.artist) \(track.name)"
        let isEastAsian = TrackQueryNormalizer.looksJapanese(metadata)
            || TrackQueryNormalizer.containsCJKIdeograph(metadata)
            || metadata.unicodeScalars.contains { scalar in
                (0xAC00...0xD7AF).contains(Int(scalar.value))
            }

        var result: [LyricsSourceKind] = []
        if playerSource == .appleMusic {
            result.append(.appleMusic)
        }
        if isEastAsian {
            result.append(contentsOf: [.lrclib, .netEase, .lyricsOvh])
        } else {
            result.append(contentsOf: [.lrclib, .lyricsOvh, .netEase])
        }
        if playerSource == nil, !result.contains(.appleMusic) {
            result.append(.appleMusic)
        }
        return result
    }
}

/// One hit from a lyrics search UI.
public struct LyricsSearchHit: Identifiable, Sendable, Equatable {
    public var id: String
    public var trackName: String
    public var artistName: String
    public var albumName: String?
    public var duration: Double?
    public var hasSynced: Bool
    public var sourceLabel: String
    /// Ready-to-display snapshot when the API already returned lyrics body.
    public var snapshot: LyricsSnapshot

    public init(
        id: String,
        trackName: String,
        artistName: String,
        albumName: String? = nil,
        duration: Double? = nil,
        hasSynced: Bool,
        sourceLabel: String,
        snapshot: LyricsSnapshot
    ) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.hasSynced = hasSynced
        self.sourceLabel = sourceLabel
        self.snapshot = snapshot
    }

    public var subtitle: String {
        var parts = [artistName]
        if let albumName, !albumName.isEmpty { parts.append(albumName) }
        if let duration = duration.flatMap(LyricsInputLimits.validDuration), duration > 0 {
            let total = Int(duration.rounded(.down))
            let m = total / 60
            let s = total % 60
            parts.append(String(format: "%d:%02d", m, s))
        }
        parts.append(sourceLabel)
        if hasSynced { parts.append("LRC") }
        return parts.joined(separator: " · ")
    }
}
