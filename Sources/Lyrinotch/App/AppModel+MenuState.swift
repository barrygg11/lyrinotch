import LyrinotchCore

@MainActor
extension AppModel {
    var menuTrackTitle: String {
        switch nowPlaying.availability {
        case .ready:
            return nowPlaying.track.displayTitle
        case .playerNotRunning, .noTrack:
            return L10n.t("track.not_playing")
        case .error:
            return nowPlaying.detail ?? L10n.t("track.not_playing")
        }
    }

    var menuPlaybackGlyph: String {
        guard nowPlaying.availability == .ready else { return "○" }
        return nowPlaying.track.isPlaying ? "▶" : "⏸"
    }

    var menuLyricsLabel: String {
        let status: String
        switch lyrics.availability {
        case .synced: status = L10n.t("lyrics.synced", lyrics.lines.count)
        case .plain: status = L10n.t("lyrics.plain", lyrics.plainLines.count)
        case .instrumental: status = L10n.t("lyrics.instrumental")
        case .notFound: status = L10n.t("lyrics.not_found")
        case .error: status = L10n.t("lyrics.error", lyrics.detail ?? "")
        case .skipped: status = L10n.t("lyrics.skipped")
        }

        var result = status
        if let source = menuLyricsSourceLabel {
            result = L10n.t("lyrics.source_append", result, source)
        }
        if let reason = lyrics.selectionReason {
            result = L10n.t("lyrics.source_append", result, L10n.t(reason.displayNameKey))
        }
        if let coverage = currentTapSyncCoverageText {
            result = L10n.t("lyrics.source_append", result, coverage)
        }
        return result
    }

    var menuLyricsSourceLabel: String? {
        switch lyrics.source?.lowercased() {
        case "lrclib": return L10n.t("lyrics_source.lrclib")
        case "apple-music": return L10n.t("lyrics_source.apple_music")
        case "netease": return L10n.t("lyrics_source.netease")
        case "lyrics.ovh": return L10n.t("lyrics_source.lyrics_ovh")
        case "local-lrc": return L10n.t("lyrics_source.local_lrc")
        case "manual-tap": return L10n.t("lyrics_source.manual_tap")
        default: return nil
        }
    }

    var launchAtLoginIsOn: Bool { LaunchAtLogin.isEnabled }
}
