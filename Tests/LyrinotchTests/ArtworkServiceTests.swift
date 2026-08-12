import AppKit
import XCTest
@testable import LyrinotchCore

private struct ArtworkURLExecutor: AppleScriptExecuting {
    var output: String
    func run(script: String) async throws -> String {
        _ = script
        return output
    }
}

private final class ArtworkURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var mimeType = "image/png"
    nonisolated(unsafe) static var data = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: [
                "Content-Type": Self.mimeType,
                "Content-Length": String(Self.data.count)
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ArtworkServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ArtworkURLProtocol.statusCode = 200
        ArtworkURLProtocol.mimeType = "image/png"
        ArtworkURLProtocol.data = Self.onePixelPNG
    }

    @MainActor
    func testRejectsNonHTTPSArtworkURLBeforeNetworkRequest() async {
        let service = ArtworkService(
            executor: ArtworkURLExecutor(output: "http://example.test/art.png"),
            session: makeSession()
        )

        let image = await service.image(for: makeTrack(), source: .spotify)

        XCTAssertNil(image)
    }

    @MainActor
    func testRejectsNonImageAndOversizedArtworkResponses() async {
        ArtworkURLProtocol.mimeType = "text/html"
        var service = ArtworkService(
            executor: ArtworkURLExecutor(output: "https://example.test/art.png"),
            session: makeSession()
        )
        let wrongType = await service.image(
            for: makeTrack(id: "wrong-type"),
            source: .spotify
        )
        XCTAssertNil(wrongType)

        ArtworkURLProtocol.mimeType = "image/png"
        ArtworkURLProtocol.data = Data(repeating: 0, count: 128)
        service = ArtworkService(
            executor: ArtworkURLExecutor(output: "https://example.test/art.png"),
            session: makeSession(),
            maximumArtworkBytes: 64
        )
        let tooLarge = await service.image(
            for: makeTrack(id: "too-large"),
            source: .spotify
        )
        XCTAssertNil(tooLarge)
    }

    @MainActor
    func testAcceptsSmallHTTPSImage() async {
        let service = ArtworkService(
            executor: ArtworkURLExecutor(output: "https://example.test/art.png"),
            session: makeSession()
        )

        let image = await service.image(for: makeTrack(), source: .spotify)
        XCTAssertNotNil(image)
    }

    @MainActor
    func testRejectsImageWhoseDecodedPixelCountExceedsLimit() async {
        ArtworkURLProtocol.data = Self.twoByTwoPNG
        let service = ArtworkService(
            executor: ArtworkURLExecutor(output: "https://example.test/art.png"),
            session: makeSession(),
            maximumArtworkPixels: 3
        )

        let image = await service.image(for: makeTrack(id: "large-pixels"), source: .spotify)

        XCTAssertNil(image)
    }

    @MainActor
    func testMusicArtworkUsesTheSamePixelLimitAndCleansTemporaryFile() async throws {
        let temporaryItems = FileManager.default.temporaryDirectory
            .appendingPathComponent("TemporaryItems", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryItems,
            withIntermediateDirectories: true
        )
        let url = temporaryItems.appendingPathComponent(
            "lyrinotch-music-art-\(UUID().uuidString).img"
        )
        try Self.twoByTwoPNG.write(to: url, options: .atomic)
        let service = ArtworkService(
            executor: ArtworkURLExecutor(output: url.path),
            session: makeSession(),
            maximumArtworkPixels: 3
        )

        let image = await service.image(
            for: makeTrack(id: "music-large-pixels", source: .appleMusic),
            source: .appleMusic
        )

        XCTAssertNil(image)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtworkURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeTrack(
        id: String = "art",
        source: MusicPlayerSource = .spotify
    ) -> Track {
        Track(
            id: id,
            name: "Song",
            artist: "Artist",
            album: "Album",
            duration: 180,
            position: 0,
            isPlaying: true,
            source: source
        )
    }

    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    private static let twoByTwoPNG: Data = {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        return bitmap.representation(using: .png, properties: [:])!
    }()
}
