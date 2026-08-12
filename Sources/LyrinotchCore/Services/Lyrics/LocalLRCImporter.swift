import Foundation

/// Resource bounds applied before a local LRC file is accepted.
///
/// The defaults are deliberately generous for normal lyrics while keeping a
/// malformed or accidentally selected file from consuming unbounded memory.
public struct LocalLRCImportLimits: Sendable, Equatable {
    public var maximumFileSizeBytes: Int
    public var maximumSourceLines: Int
    public var maximumTimedLines: Int
    public var maximumCharactersPerLine: Int

    public init(
        maximumFileSizeBytes: Int = 1_048_576,
        maximumSourceLines: Int = 20_000,
        maximumTimedLines: Int = 10_000,
        maximumCharactersPerLine: Int = 16_384
    ) {
        self.maximumFileSizeBytes = max(1, maximumFileSizeBytes)
        self.maximumSourceLines = max(1, maximumSourceLines)
        self.maximumTimedLines = max(1, maximumTimedLines)
        self.maximumCharactersPerLine = max(1, maximumCharactersPerLine)
    }

    public static let standard = LocalLRCImportLimits()
}

/// Encoding detected while reading a local LRC file.
public enum LocalLRCTextEncoding: String, Codable, Sendable, Equatable {
    case utf8 = "utf-8"
    case utf16LittleEndian = "utf-16le"
    case utf16BigEndian = "utf-16be"
}

/// Non-lyric information retained from an imported LRC file.
///
/// `originalFileName` is the final path component only; the user's local path
/// is intentionally never stored in `LyricsSnapshot` or preferences.
public struct LocalLRCMetadata: Sendable, Equatable {
    public var originalFileName: String
    public var title: String?
    public var artist: String?
    public var album: String?
    public var creator: String?
    public var duration: TimeInterval?
    public var embeddedOffsetSeconds: TimeInterval
    public var encoding: LocalLRCTextEncoding
    public var sourceLineCount: Int
    public var timedLineCount: Int
    public var usableTimedLineCount: Int
    public var contentIdentifier: String

    public init(
        originalFileName: String,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        creator: String? = nil,
        duration: TimeInterval? = nil,
        embeddedOffsetSeconds: TimeInterval = 0,
        encoding: LocalLRCTextEncoding,
        sourceLineCount: Int,
        timedLineCount: Int,
        usableTimedLineCount: Int,
        contentIdentifier: String
    ) {
        self.originalFileName = originalFileName
        self.title = title
        self.artist = artist
        self.album = album
        self.creator = creator
        self.duration = duration
        self.embeddedOffsetSeconds = embeddedOffsetSeconds
        self.encoding = encoding
        self.sourceLineCount = sourceLineCount
        self.timedLineCount = timedLineCount
        self.usableTimedLineCount = usableTimedLineCount
        self.contentIdentifier = contentIdentifier
    }
}

/// A validated local LRC file and the snapshot ready for display/persistence.
public struct LocalLRCImportResult: Sendable, Equatable {
    public let snapshot: LyricsSnapshot
    public let metadata: LocalLRCMetadata

    init(snapshot: LyricsSnapshot, metadata: LocalLRCMetadata) {
        self.snapshot = snapshot
        self.metadata = metadata
    }

    /// Returns a 0...100 identity score when the LRC carries title or artist metadata.
    /// A UI can use this to warn about a likely wrong-version import without rejecting
    /// an explicit manual choice solely because optional LRC tags are absent.
    public func matchConfidence(for track: Track) -> Int? {
        guard metadata.title != nil || metadata.artist != nil else { return nil }
        return TrackQueryNormalizer.identityConfidence(
            wantArtist: track.artist,
            wantTitle: track.name,
            gotArtist: metadata.artist,
            gotTitle: metadata.title,
            wantDuration: track.duration,
            gotDuration: metadata.duration
        )
    }
}

/// Typed failures intentionally carry no localized UI strings. Callers can map
/// each case to the application's active language while `errorDescription`
/// remains a useful fallback for logs and non-GUI clients.
public enum LocalLRCImportError: Error, Sendable, Equatable, LocalizedError {
    case notFileURL
    case unsupportedFileExtension
    case notRegularFile
    case unreadableFile
    case fileTooLarge(maximumBytes: Int)
    case emptyFile
    case unsupportedEncoding
    case invalidTextContent
    case tooManySourceLines(maximum: Int)
    case lineTooLong(maximumCharacters: Int)
    case noTimedLyrics
    case noUsableTimedLyrics
    case tooManyTimedLines(maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .notFileURL:
            return "The selected item is not a local file"
        case .unsupportedFileExtension:
            return "The selected file is not an LRC file"
        case .notRegularFile:
            return "The selected item is not a regular file"
        case .unreadableFile:
            return "The selected LRC file could not be read"
        case .fileTooLarge(let maximumBytes):
            return "The selected LRC file exceeds the \(maximumBytes)-byte limit"
        case .emptyFile:
            return "The selected LRC file is empty"
        case .unsupportedEncoding:
            return "The selected LRC file is not valid UTF-8 or BOM-marked UTF-16"
        case .invalidTextContent:
            return "The selected LRC file contains invalid text"
        case .tooManySourceLines(let maximum):
            return "The selected LRC file exceeds the \(maximum)-line source limit"
        case .lineTooLong(let maximumCharacters):
            return "An LRC source line exceeds the \(maximumCharacters)-character limit"
        case .noTimedLyrics:
            return "The selected LRC file has no timed lyric lines"
        case .noUsableTimedLyrics:
            return "The selected LRC file has no non-empty timed lyric lines"
        case .tooManyTimedLines(let maximum):
            return "The selected LRC file exceeds the \(maximum)-line timeline limit"
        }
    }
}

/// Loads and validates user-selected local `.lrc` files without contacting a
/// lyrics provider or retaining access to the original file.
public struct LocalLRCImporter: Sendable {
    public static let sourceIdentifier = "local-lrc"

    public var limits: LocalLRCImportLimits

    public init(limits: LocalLRCImportLimits = .standard) {
        self.limits = limits
    }

    /// Reads a security-scoped file URL, then releases access before returning.
    public func load(from fileURL: URL) throws -> LocalLRCImportResult {
        guard fileURL.isFileURL else { throw LocalLRCImportError.notFileURL }
        guard fileURL.pathExtension.lowercased() == "lrc" else {
            throw LocalLRCImportError.unsupportedFileExtension
        }

        let didAccessSecurityScope = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let values: URLResourceValues
        do {
            values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw LocalLRCImportError.unreadableFile
        }
        guard values.isRegularFile == true else {
            throw LocalLRCImportError.notRegularFile
        }
        if let size = values.fileSize, size > limits.maximumFileSizeBytes {
            throw LocalLRCImportError.fileTooLarge(maximumBytes: limits.maximumFileSizeBytes)
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: fileURL)
        } catch {
            throw LocalLRCImportError.unreadableFile
        }
        defer { try? handle.close() }

        let data: Data
        do {
            // Reading one extra byte makes the post-open size check race-safe.
            let (readLimit, overflow) = limits.maximumFileSizeBytes.addingReportingOverflow(1)
            data = try handle.read(
                upToCount: overflow ? limits.maximumFileSizeBytes : readLimit
            ) ?? Data()
        } catch {
            throw LocalLRCImportError.unreadableFile
        }
        return try load(data: data, fileName: fileURL.lastPathComponent)
    }

    /// Validates already-loaded bytes. This is useful for tests and for callers
    /// that receive file contents through another trusted document API.
    public func load(
        data: Data,
        fileName: String = "Imported.lrc"
    ) throws -> LocalLRCImportResult {
        guard !data.isEmpty else { throw LocalLRCImportError.emptyFile }
        guard data.count <= limits.maximumFileSizeBytes else {
            throw LocalLRCImportError.fileTooLarge(maximumBytes: limits.maximumFileSizeBytes)
        }

        let decoded = try decode(data)
        let text = decoded.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalLRCImportError.emptyFile
        }
        guard !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw LocalLRCImportError.invalidTextContent
        }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let sourceLines = normalized.components(separatedBy: .newlines)
        guard sourceLines.count <= limits.maximumSourceLines else {
            throw LocalLRCImportError.tooManySourceLines(maximum: limits.maximumSourceLines)
        }
        guard sourceLines.allSatisfy({ $0.count <= limits.maximumCharactersPerLine }) else {
            throw LocalLRCImportError.lineTooLong(
                maximumCharacters: limits.maximumCharactersPerLine
            )
        }

        let parserMaximum = limits.maximumTimedLines == Int.max
            ? Int.max
            : limits.maximumTimedLines + 1
        let timedLines = LRCParser.parse(
            normalized,
            maximumLines: parserMaximum
        )
        guard !timedLines.isEmpty else { throw LocalLRCImportError.noTimedLyrics }
        guard timedLines.count <= limits.maximumTimedLines else {
            throw LocalLRCImportError.tooManyTimedLines(maximum: limits.maximumTimedLines)
        }
        let embeddedOffset = LRCParser.embeddedOffsetSeconds(in: normalized)
        guard embeddedOffset.isFinite, timedLines.allSatisfy({ $0.time.isFinite }) else {
            throw LocalLRCImportError.invalidTextContent
        }
        let usableCount = timedLines.lazy.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        guard usableCount > 0 else { throw LocalLRCImportError.noUsableTimedLyrics }

        let tags = Self.metadataTags(in: sourceLines)
        let contentIdentifier = Self.contentIdentifier(for: normalized)
        let safeFileName = Self.safeFileName(fileName)
        let metadata = LocalLRCMetadata(
            originalFileName: safeFileName,
            title: tags["ti"],
            artist: tags["ar"],
            album: tags["al"],
            creator: tags["by"],
            duration: tags["length"].flatMap(Self.parseDuration),
            embeddedOffsetSeconds: embeddedOffset,
            encoding: decoded.encoding,
            sourceLineCount: sourceLines.count,
            timedLineCount: timedLines.count,
            usableTimedLineCount: usableCount,
            contentIdentifier: contentIdentifier
        )
        let matchedTrack = LyricsMatchMetadata(
            title: metadata.title ?? "",
            artist: metadata.artist ?? "",
            duration: metadata.duration,
            providerID: contentIdentifier
        )
        let snapshot = LyricsSnapshot(
            availability: .synced,
            lines: timedLines,
            source: Self.sourceIdentifier,
            detail: "encoding=\(decoded.encoding.rawValue);lines=\(timedLines.count)",
            matchedTrack: matchedTrack,
            selectionReason: .manuallySelected
        )
        return LocalLRCImportResult(snapshot: snapshot, metadata: metadata)
    }

    private func decode(_ data: Data) throws -> (text: String, encoding: LocalLRCTextEncoding) {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let text = String(data: data.dropFirst(3), encoding: .utf8) else {
                throw LocalLRCImportError.unsupportedEncoding
            }
            return (text, .utf8)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) else {
                throw LocalLRCImportError.unsupportedEncoding
            }
            return (text, .utf16LittleEndian)
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) else {
                throw LocalLRCImportError.unsupportedEncoding
            }
            return (text, .utf16BigEndian)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw LocalLRCImportError.unsupportedEncoding
        }
        return (text, .utf8)
    }

    private static func metadataTags(in lines: [String]) -> [String: String] {
        let supported = Set(["ti", "ar", "al", "by", "length"])
        var result: [String: String] = [:]
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.first == "[", line.last == "]", !line.contains("][") else { continue }
            let body = line.dropFirst().dropLast()
            guard let separator = body.firstIndex(of: ":") else { continue }
            let key = body[..<separator].lowercased()
            guard supported.contains(key), result[key] == nil else { continue }
            let valueStart = body.index(after: separator)
            let value = body[valueStart...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            // Metadata is only advisory; cap it so it cannot become an oversized
            // persisted identity even when the source-line bound is much larger.
            result[key] = String(value.prefix(512))
        }
        return result
    }

    private static func parseDuration(_ raw: String) -> TimeInterval? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let seconds = Double(parts.last ?? ""),
              seconds.isFinite, seconds >= 0, seconds < 60
        else { return nil }

        if parts.count == 2 {
            guard let minutes = Double(parts[0]), minutes.isFinite, minutes >= 0 else {
                return nil
            }
            let duration = minutes * 60 + seconds
            return LyricsInputLimits.validDuration(duration)
        }
        guard let hours = Double(parts[0]), hours.isFinite, hours >= 0,
              let minutes = Double(parts[1]), minutes.isFinite, minutes >= 0, minutes < 60
        else { return nil }
        let duration = hours * 3_600 + minutes * 60 + seconds
        return LyricsInputLimits.validDuration(duration)
    }

    private static func safeFileName(_ raw: String) -> String {
        let name = URL(fileURLWithPath: raw).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let printable = name.filter { character in
            !character.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
        }
        let bounded = String(printable.prefix(255))
        return bounded.isEmpty ? "Imported.lrc" : bounded
    }

    private static func contentIdentifier(for text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(format: "lrc-v1:%016llx", hash)
    }
}
