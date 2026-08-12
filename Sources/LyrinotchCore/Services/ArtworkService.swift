import AppKit
import Foundation
import ImageIO

/// Loads album artwork for the current track (Spotify URL or Music.app raw data).
public actor ArtworkService {
    private let executor: any AppleScriptExecuting
    private let session: URLSession
    private let maximumArtworkBytes: Int
    private let maximumArtworkPixels: Int
    private var cache: [TrackIdentity: Data] = [:]
    private var lastIdentity: TrackIdentity?

    public init(
        executor: any AppleScriptExecuting = ProcessAppleScriptExecutor(),
        session: URLSession = .shared,
        maximumArtworkBytes: Int = 5_000_000,
        maximumArtworkPixels: Int = 32_000_000
    ) {
        self.executor = executor
        self.session = session
        self.maximumArtworkBytes = max(1, maximumArtworkBytes)
        self.maximumArtworkPixels = max(1, maximumArtworkPixels)
    }

    /// Returns artwork for `track` / `source`, using an in-memory cache per track id.
    @MainActor
    public func image(for track: Track, source: MusicPlayerSource?) async -> NSImage? {
        guard let data = await imageData(for: track, source: source) else { return nil }
        return NSImage(data: data)
    }

    private func imageData(for track: Track, source: MusicPlayerSource?) async -> Data? {
        guard let resolvedSource = track.source ?? source, !track.name.isEmpty else { return nil }
        let identity = TrackIdentity(track: track, source: resolvedSource)
        if let cached = cache[identity] { return cached }

        let data: Data?
        switch resolvedSource {
        case .spotify:
            data = await fetchSpotifyArtwork()
        case .appleMusic:
            data = await fetchMusicArtwork()
        }

        if let data {
            cache[identity] = data
            // Keep cache small.
            if cache.count > 24, let lastIdentity, lastIdentity != identity {
                cache.removeValue(forKey: lastIdentity)
            }
            lastIdentity = identity
        }
        return data
    }

    public func clearCache() {
        cache.removeAll()
        lastIdentity = nil
    }

    private func fetchSpotifyArtwork() async -> Data? {
        do {
            let raw = try await executor.run(script: SpotifyAppleScript.artworkURLScript)
            let urlString = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlString.isEmpty,
                  let url = URL(string: urlString),
                  url.scheme?.lowercased() == "https"
            else { return nil }
            let loaded = try await BoundedResponseLoader.data(
                for: URLRequest(url: url),
                in: session,
                maximumBytes: maximumArtworkBytes
            )
            let http = loaded.response
            guard http.url?.scheme?.lowercased() == "https",
                  (200..<300).contains(http.statusCode),
                  http.mimeType?.lowercased().hasPrefix("image/") == true,
                  http.expectedContentLength <= 0
                    || http.expectedContentLength <= Int64(maximumArtworkBytes)
            else { return nil }
            return validatedImage(from: loaded.data)
        } catch {
            return nil
        }
    }

    private func fetchMusicArtwork() async -> Data? {
        do {
            let raw = try await executor.run(script: MusicAppleScript.artworkFileScript)
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let resolvedParent = url.deletingLastPathComponent()
                .resolvingSymlinksInPath()
            let isAllowedTemporaryParent = resolvedParent == temporaryDirectory
                || (resolvedParent.lastPathComponent == "TemporaryItems"
                    && resolvedParent.deletingLastPathComponent() == temporaryDirectory)
            guard isAllowedTemporaryParent,
                  url.lastPathComponent.hasPrefix("lyrinotch-music-art-"),
                  url.pathExtension == "img"
            else { return nil }
            defer { try? FileManager.default.removeItem(at: url) }
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let fileSize = values.fileSize,
                  fileSize > 0,
                  fileSize <= maximumArtworkBytes
            else { return nil }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= maximumArtworkBytes else { return nil }
            return validatedImage(from: data)
        } catch {
            return nil
        }
    }

    /// Inspect encoded dimensions before the main actor constructs NSImage.
    /// This prevents a tiny compressed payload from expanding into an unbounded
    /// bitmap later when artwork colors are sampled.
    private func validatedImage(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0,
              width <= 8_192,
              height <= 8_192,
              width <= maximumArtworkPixels / height
        else { return nil }
        return data
    }
}
