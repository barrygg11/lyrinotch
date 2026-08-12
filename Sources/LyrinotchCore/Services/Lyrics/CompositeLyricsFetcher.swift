import Foundation

public enum CompositeLyricsError: Error, LocalizedError, Sendable, Equatable {
    case allProvidersFailed([String])

    public var errorDescription: String? {
        switch self {
        case .allProvidersFailed(let failures):
            return "All lyrics providers failed: " + failures.joined(separator: "; ")
        }
    }
}

/// Tries multiple lyrics providers according to user preference order.
/// Rejects low-confidence hits so a later high-confidence source can win
/// (or we show “not found” instead of random lyrics).
public struct CompositeLyricsFetcher: LyricsFetching {
    public var preference: LyricsSourcePreference
    public var lrclib: LRCLIBClient
    public var appleMusic: AppleMusicLyricsFetcher
    public var netEase: NetEaseLyricsClient
    public var lyricsOvh: LyricsOvhClient
    /// Optional: skip Apple Music source unless player is Music (or unknown).
    public var playerSource: MusicPlayerSource?
    private var providerFetchOverride: (@Sendable (LyricsSourceKind, Track) async throws -> LyricsSnapshot)?

    public init(
        preference: LyricsSourcePreference = .lrclibOnly,
        lrclib: LRCLIBClient = LRCLIBClient(),
        appleMusic: AppleMusicLyricsFetcher = AppleMusicLyricsFetcher(),
        netEase: NetEaseLyricsClient = NetEaseLyricsClient(),
        lyricsOvh: LyricsOvhClient = LyricsOvhClient(),
        playerSource: MusicPlayerSource? = nil,
        providerFetchOverride: (@Sendable (LyricsSourceKind, Track) async throws -> LyricsSnapshot)? = nil
    ) {
        self.preference = preference
        self.lrclib = lrclib
        self.appleMusic = appleMusic
        self.netEase = netEase
        self.lyricsOvh = lyricsOvh
        self.playerSource = playerSource
        self.providerFetchOverride = providerFetchOverride
    }

    public func fetch(for track: Track) async throws -> LyricsSnapshot {
        var best: (snap: LyricsSnapshot, score: Int, kind: LyricsSourceKind)?
        var attemptedCount = 0
        var attemptedKinds: [LyricsSourceKind] = []
        var failures: [String] = []

        for kind in preference.pipeline(for: track, playerSource: playerSource) {
            try Task.checkCancellation()
            if kind == .appleMusic {
                if let playerSource, playerSource != .appleMusic {
                    continue
                }
            }
            attemptedCount += 1
            attemptedKinds.append(kind)
            let snap: LyricsSnapshot
            do {
                snap = try await fetch(kind: kind, track: track)
            } catch {
                try Task.checkCancellation()
                failures.append("\(kind.rawValue): \(error.localizedDescription)")
                continue
            }
            guard isUsable(snap) else { continue }

            let assessment = confidence(for: snap, track: track, kind: kind)
            let score = assessment.total
            // Soft sources (NetEase / ovh) must clear the identity bar.
            if kind == .netEase || kind == .lyricsOvh {
                if assessment.identity < TrackQueryNormalizer.minimumAcceptIdentity { continue }
            }
            if let current = best {
                let newRank = rank(snap.availability)
                let currentRank = rank(current.snap.availability)
                // A confidently matched timed source must beat plain text,
                // regardless of a small provider-priority score difference.
                if newRank > currentRank {
                    best = (snap, score, kind)
                } else if newRank == currentRank, score > current.score + 8 {
                    best = (snap, score, kind)
                }
            } else if score >= TrackQueryNormalizer.minimumAcceptIdentity || kind == .lrclib {
                // LRCLIB already self-filters; accept when it returns usable content.
                best = (
                    snap,
                    max(score, kind == .lrclib ? TrackQueryNormalizer.minimumAcceptIdentity : score),
                    kind
                )
            }

            // High-confidence synced hit — stop early.
            if let best,
               best.score >= 70,
               best.snap.availability == .synced,
               languageAffinity(for: best.snap, track: track) >= 0
            {
                return annotated(
                    best.snap,
                    kind: best.kind,
                    score: best.score,
                    track: track,
                    firstAttempted: attemptedKinds.first
                )
            }
        }

        if let best, best.score >= TrackQueryNormalizer.minimumAcceptIdentity {
            return annotated(
                best.snap,
                kind: best.kind,
                score: best.score,
                track: track,
                firstAttempted: attemptedKinds.first
            )
        }
        if attemptedCount > 0, failures.count == attemptedCount {
            throw CompositeLyricsError.allProvidersFailed(failures)
        }
        // Prefer honest not-found over a weak/random match.
        return LyricsSnapshot(availability: .notFound, source: "composite", detail: "No confident match")
    }

    private func fetch(kind: LyricsSourceKind, track: Track) async throws -> LyricsSnapshot {
        if let providerFetchOverride {
            return try await providerFetchOverride(kind, track)
        }
        switch kind {
        case .lrclib:
            return try await lrclib.fetch(for: track)
        case .appleMusic:
            return try await appleMusic.fetch(for: track)
        case .netEase:
            return try await netEase.fetch(for: track)
        case .lyricsOvh:
            return try await lyricsOvh.fetch(for: track)
        }
    }

    private func isUsable(_ snap: LyricsSnapshot) -> Bool {
        switch snap.availability {
        case .synced, .plain, .instrumental:
            return true
        default:
            return false
        }
    }

    private func rank(_ a: LyricsAvailability) -> Int {
        switch a {
        case .synced: return 3
        case .plain: return 2
        case .instrumental: return 1
        default: return 0
        }
    }

    /// Rough confidence for cross-source comparison.
    private func confidence(
        for snap: LyricsSnapshot,
        track: Track,
        kind: LyricsSourceKind
    ) -> (total: Int, identity: Int) {
        // Prefer structured provider identity. The detail parser is a legacy
        // fallback for custom providers and older snapshots.
        let gotTitle: String?
        let gotArtist: String?
        let gotDuration: TimeInterval?
        if let matched = snap.matchedTrack,
           !matched.title.isEmpty,
           !matched.artist.isEmpty
        {
            gotArtist = matched.artist
            gotTitle = matched.title
            gotDuration = matched.duration
        } else if let parsed = parseMatchedIdentity(snap.detail) {
            gotArtist = parsed.artist
            gotTitle = parsed.title
            gotDuration = nil
        } else if kind == .netEase || kind == .lyricsOvh {
            // Missing identity → treat as unknown so soft sources fail the bar.
            gotArtist = nil
            gotTitle = nil
            gotDuration = nil
        } else {
            gotTitle = track.name
            gotArtist = track.artist
            // LRCLIB self-filters and Music.app is the active local track.
            gotDuration = track.duration
        }

        let identity = TrackQueryNormalizer.identityConfidence(
            wantArtist: track.artist,
            wantTitle: track.name,
            gotArtist: gotArtist,
            gotTitle: gotTitle,
            wantDuration: track.duration,
            gotDuration: gotDuration
        )
        var score = identity

        switch snap.availability {
        case .synced: score += 15
        case .plain: score += 5
        default: break
        }
        switch kind {
        case .lrclib: score += 5
        case .appleMusic: score += 20
        case .netEase: break
        case .lyricsOvh: score -= 5 // plain-only, path-based
        }
        score += languageAffinity(for: snap, track: track)
        return (score, identity)
    }

    private func annotated(
        _ snapshot: LyricsSnapshot,
        kind: LyricsSourceKind,
        score: Int,
        track: Track,
        firstAttempted: LyricsSourceKind?
    ) -> LyricsSnapshot {
        var result = snapshot
        if kind == .appleMusic {
            result.selectionReason = .playerEmbedded
        } else if snapshot.availability == .plain {
            result.selectionReason = .plainTextFallback
        } else if languageAffinity(for: snapshot, track: track) > 0 {
            result.selectionReason = .languageMatch
        } else if kind != firstAttempted {
            result.selectionReason = .fallbackSource
        } else if score >= 70, snapshot.availability == .synced {
            result.selectionReason = .strongSyncedMatch
        } else {
            result.selectionReason = .fallbackSource
        }
        return result
    }

    private func languageAffinity(for snapshot: LyricsSnapshot, track: Track) -> Int {
        let metadata = "\(track.artist) \(track.name)"
        let body = snapshot.lines.map(\.text).joined(separator: " ")
            + " " + snapshot.plainLines.joined(separator: " ")
        if TrackQueryNormalizer.looksJapanese(metadata) {
            return TrackQueryNormalizer.looksJapanese(body) ? 10 : -8
        }
        let metadataIsEastAsian = TrackQueryNormalizer.containsCJKIdeograph(metadata)
            || containsHangul(metadata)
        guard metadataIsEastAsian else { return 0 }
        return TrackQueryNormalizer.containsCJKIdeograph(body) || containsHangul(body) ? 8 : -5
    }

    private func containsHangul(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0xAC00...0xD7AF).contains(Int(scalar.value))
        }
    }

    private func parseMatchedIdentity(_ detail: String?) -> (artist: String, title: String)? {
        guard let detail, detail.contains("—") else { return nil }
        let parts = detail.split(separator: "—", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }
}
