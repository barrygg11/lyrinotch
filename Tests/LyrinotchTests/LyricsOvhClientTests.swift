import XCTest
@testable import LyrinotchCore

private final class LyricsOvhRequestStore: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var data = Data()
    private var requests: [URLRequest] = []

    func configure(status: Int, data: Data) {
        lock.withLock {
            self.status = status
            self.data = data
            requests = []
        }
    }

    func response(for request: URLRequest) -> (Int, Data) {
        lock.withLock {
            requests.append(request)
            return (status, data)
        }
    }

    var lastURL: URL? { lock.withLock { requests.last?.url } }
}

private final class LyricsOvhURLProtocol: URLProtocol, @unchecked Sendable {
    static let store = LyricsOvhRequestStore()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result = Self.store.response(for: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: result.0,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LyricsOvhClientTests: XCTestCase {
    func testEncodesSlashesAsPartOfArtistAndTitle() async throws {
        LyricsOvhURLProtocol.store.configure(
            status: 200,
            data: Data(#"{"lyrics":"first\nsecond"}"#.utf8)
        )
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = LyricsOvhClient(session: session)
        let track = Track(
            id: "track",
            name: "Rock/Role?",
            artist: "AC/DC",
            album: nil,
            duration: 180,
            position: 0,
            isPlaying: true
        )

        let snapshot = try await client.fetch(for: track)

        XCTAssertEqual(snapshot.availability, .plain)
        XCTAssertTrue(LyricsOvhURLProtocol.store.lastURL?.absoluteString.contains("AC%2FDC") == true)
        XCTAssertEqual(snapshot.matchedTrack?.artist, "AC/DC")
    }

    func testSurfacesHTTPFailureInsteadOfCachingNotFound() async {
        LyricsOvhURLProtocol.store.configure(status: 503, data: Data())
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = LyricsOvhClient(session: session)
        let track = Track(
            id: "track",
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 180,
            position: 0,
            isPlaying: true
        )

        do {
            _ = try await client.fetch(for: track)
            XCTFail("Expected LyricsOvhError")
        } catch let error as LyricsOvhError {
            XCTAssertEqual(error, .httpStatus(503))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsOversizedResponseBody() async {
        let oversizedLyrics = String(repeating: "a", count: 1_100_000)
        let body = Data("{\"lyrics\":\"\(oversizedLyrics)\"}".utf8)
        LyricsOvhURLProtocol.store.configure(status: 200, data: body)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = LyricsOvhClient(session: session)
        let track = Track(
            id: "track",
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 180,
            position: 0,
            isPlaying: true
        )

        do {
            _ = try await client.fetch(for: track)
            XCTFail("Expected oversized response to be rejected")
        } catch let error as LyricsOvhError {
            XCTAssertEqual(error, .malformedResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsOvhURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
