import Foundation
import XCTest
@testable import LyrinotchCore

final class LocalLRCImporterTests: XCTestCase {
    func testBuildsSyncedSnapshotAndRetainsSafeMetadata() throws {
        let lrc = """
        [ti:Example Song]
        [ar:Example Artist]
        [al:Example Album]
        [by:Timing Editor]
        [length:03:05.50]
        [offset:-250]
        [00:01.00]First line
        [00:02.50][00:04.00]Repeated line
        [00:05.00]
        """

        let imported = try LocalLRCImporter().load(
            data: Data(lrc.utf8),
            fileName: "/private/user/Example.lrc"
        )

        XCTAssertEqual(imported.snapshot.availability, .synced)
        XCTAssertEqual(imported.snapshot.source, LocalLRCImporter.sourceIdentifier)
        XCTAssertEqual(imported.snapshot.selectionReason, .manuallySelected)
        XCTAssertEqual(imported.snapshot.lines.count, 4)
        XCTAssertEqual(imported.snapshot.lines[0].time, 0.75, accuracy: 0.001)
        XCTAssertEqual(imported.snapshot.lines[1].time, 2.25, accuracy: 0.001)
        XCTAssertEqual(imported.snapshot.lines[2].time, 3.75, accuracy: 0.001)
        XCTAssertEqual(imported.metadata.originalFileName, "Example.lrc")
        XCTAssertEqual(imported.metadata.title, "Example Song")
        XCTAssertEqual(imported.metadata.artist, "Example Artist")
        XCTAssertEqual(imported.metadata.album, "Example Album")
        XCTAssertEqual(imported.metadata.creator, "Timing Editor")
        XCTAssertEqual(imported.metadata.duration ?? 0, 185.5, accuracy: 0.001)
        XCTAssertEqual(imported.metadata.embeddedOffsetSeconds, -0.25, accuracy: 0.001)
        XCTAssertEqual(imported.metadata.encoding, .utf8)
        XCTAssertEqual(imported.metadata.timedLineCount, 4)
        XCTAssertEqual(imported.metadata.usableTimedLineCount, 3)
        XCTAssertEqual(
            imported.snapshot.matchedTrack?.providerID,
            imported.metadata.contentIdentifier
        )
        XCTAssertFalse(imported.snapshot.detail?.contains("Example.lrc") ?? true)

        let track = Track(
            id: "example",
            name: "Example Song",
            artist: "Example Artist",
            album: "Example Album",
            duration: 185.5,
            position: 0,
            isPlaying: true
        )
        XCTAssertEqual(imported.matchConfidence(for: track), 100)
    }

    func testLoadsUppercaseLRCExtensionFromFileURL() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalLRCImporter-\(UUID().uuidString).LRC")
        try Data("[00:01.00]One\n[00:02.00]Two".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let imported = try LocalLRCImporter().load(from: fileURL)

        XCTAssertEqual(imported.metadata.originalFileName, fileURL.lastPathComponent)
        XCTAssertEqual(imported.snapshot.lines.map(\.text), ["One", "Two"])
    }

    func testDecodesUTF16LittleAndBigEndianWithBOM() throws {
        let lrc = "[00:01.00]第一行\n[00:02.00]第二行"
        let littleBody = try XCTUnwrap(lrc.data(using: .utf16LittleEndian))
        let bigBody = try XCTUnwrap(lrc.data(using: .utf16BigEndian))
        var little = Data([0xFF, 0xFE])
        little.append(littleBody)
        var big = Data([0xFE, 0xFF])
        big.append(bigBody)

        let littleImport = try LocalLRCImporter().load(data: little)
        let bigImport = try LocalLRCImporter().load(data: big)

        XCTAssertEqual(littleImport.metadata.encoding, .utf16LittleEndian)
        XCTAssertEqual(bigImport.metadata.encoding, .utf16BigEndian)
        XCTAssertEqual(littleImport.snapshot.lines, bigImport.snapshot.lines)
        XCTAssertEqual(littleImport.snapshot.lines.map(\.text), ["第一行", "第二行"])
    }

    func testRejectsNonFileURLAndWrongExtension() {
        XCTAssertThrowsError(try LocalLRCImporter().load(from: URL(string: "https://example.test/a.lrc")!)) {
            XCTAssertEqual($0 as? LocalLRCImportError, .notFileURL)
        }
        let textURL = FileManager.default.temporaryDirectory.appendingPathComponent("lyrics.txt")
        XCTAssertThrowsError(try LocalLRCImporter().load(from: textURL)) {
            XCTAssertEqual($0 as? LocalLRCImportError, .unsupportedFileExtension)
        }
    }

    func testRejectsDirectoryEvenWhenNamedLRC() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalLRCImporter-\(UUID().uuidString).lrc", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try LocalLRCImporter().load(from: directory)) {
            XCTAssertEqual($0 as? LocalLRCImportError, .notRegularFile)
        }
    }

    func testRejectsEmptyUnsupportedAndInvalidTextFiles() {
        let importer = LocalLRCImporter()
        XCTAssertThrowsError(try importer.load(data: Data())) {
            XCTAssertEqual($0 as? LocalLRCImportError, .emptyFile)
        }
        XCTAssertThrowsError(try importer.load(data: Data([0xC3, 0x28]))) {
            XCTAssertEqual($0 as? LocalLRCImportError, .unsupportedEncoding)
        }
        XCTAssertThrowsError(try importer.load(data: Data("[00:01.00]A\0B".utf8))) {
            XCTAssertEqual($0 as? LocalLRCImportError, .invalidTextContent)
        }
    }

    func testEnforcesFileSourceLineAndCharacterBounds() {
        let byteLimited = LocalLRCImporter(
            limits: LocalLRCImportLimits(maximumFileSizeBytes: 8)
        )
        XCTAssertThrowsError(try byteLimited.load(data: Data(repeating: 0x41, count: 9))) {
            XCTAssertEqual($0 as? LocalLRCImportError, .fileTooLarge(maximumBytes: 8))
        }

        let lineLimited = LocalLRCImporter(
            limits: LocalLRCImportLimits(maximumSourceLines: 2)
        )
        XCTAssertThrowsError(
            try lineLimited.load(data: Data("[00:01]A\n[00:02]B\n[00:03]C".utf8))
        ) {
            XCTAssertEqual($0 as? LocalLRCImportError, .tooManySourceLines(maximum: 2))
        }

        let characterLimited = LocalLRCImporter(
            limits: LocalLRCImportLimits(maximumCharactersPerLine: 12)
        )
        XCTAssertThrowsError(
            try characterLimited.load(data: Data("[00:01.00]Long text".utf8))
        ) {
            XCTAssertEqual($0 as? LocalLRCImportError, .lineTooLong(maximumCharacters: 12))
        }
    }

    func testRejectsMissingEmptyAndOversizedTimedTimeline() {
        let importer = LocalLRCImporter()
        XCTAssertThrowsError(try importer.load(data: Data("plain lyrics only".utf8))) {
            XCTAssertEqual($0 as? LocalLRCImportError, .noTimedLyrics)
        }
        XCTAssertThrowsError(try importer.load(data: Data("[00:01]\n[00:02]   ".utf8))) {
            XCTAssertEqual($0 as? LocalLRCImportError, .noUsableTimedLyrics)
        }

        let timedLimited = LocalLRCImporter(
            limits: LocalLRCImportLimits(maximumTimedLines: 2)
        )
        XCTAssertThrowsError(
            try timedLimited.load(data: Data("[00:01][00:02][00:03]Repeated".utf8))
        ) {
            XCTAssertEqual($0 as? LocalLRCImportError, .tooManyTimedLines(maximum: 2))
        }
    }

    func testMetadataFreeImportDoesNotClaimIdentityConfidence() throws {
        let imported = try LocalLRCImporter().load(data: Data("[00:01]One".utf8))
        let track = Track(
            id: nil,
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 180,
            position: 0,
            isPlaying: true
        )

        XCTAssertNil(imported.matchConfidence(for: track))
    }

    func testLyricsServicePinsImportedLRCWithoutCallingFetcher() async throws {
        let pinnedStore = PinnedLyricsStore.ephemeral()
        let imported = try LocalLRCImporter().load(
            data: Data("[ti:Song]\n[ar:Artist]\n[00:01]Imported".utf8)
        )
        let track = Track(
            id: "local-import",
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 180,
            position: 0,
            isPlaying: true,
            source: .spotify
        )
        let service = LyricsService(
            fetcher: LocalLRCUnexpectedFetcher(),
            pinnedLyricsStore: pinnedStore
        )
        await service.setPlayerSource(.spotify)

        let applied = await service.apply(importedLRC: imported, to: track)
        let cached = await service.snapshot(for: track)

        XCTAssertEqual(applied.source, LocalLRCImporter.sourceIdentifier)
        XCTAssertEqual(cached, applied)

        let relaunched = LyricsService(
            fetcher: LocalLRCUnexpectedFetcher(),
            pinnedLyricsStore: pinnedStore
        )
        await relaunched.setPlayerSource(.spotify)
        let persisted = await relaunched.snapshot(for: track)
        XCTAssertEqual(persisted, applied)
    }
}

private struct LocalLRCUnexpectedFetcher: LyricsFetching {
    func fetch(for track: Track) async throws -> LyricsSnapshot {
        _ = track
        return LyricsSnapshot(availability: .error, detail: "unexpected provider fetch")
    }
}
