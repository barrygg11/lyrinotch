import XCTest
@testable import LyrinotchCore

private final class NetEaseRequestRouter: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, data: Data)

    private let lock = NSLock()
    private var handler: Handler = { _ in (404, Data()) }
    private var requests: [URLRequest] = []

    func configure(_ handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
            requests = []
        }
    }

    func response(for request: URLRequest) -> (status: Int, data: Data) {
        let current = lock.withLock { () -> Handler in
            requests.append(request)
            return handler
        }
        return current(request)
    }

    var recordedRequests: [URLRequest] { lock.withLock { requests } }
}

private final class NetEaseURLProtocol: URLProtocol, @unchecked Sendable {
    static let router = NetEaseRequestRouter()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result = Self.router.response(for: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: result.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class NetEaseLyricsClientTests: XCTestCase {
    func testValidEmptySearchDoesNotRetryAsPOST() async throws {
        let emptySearch = Data(#"{"result":{"songs":[]}}"#.utf8)
        NetEaseURLProtocol.router.configure { _ in (200, emptySearch) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = NetEaseLyricsClient(session: session, maxAutomaticSearches: 5)

        let snapshot = try await client.fetch(for: track)

        XCTAssertEqual(snapshot.availability, .notFound)
        let requests = NetEaseURLProtocol.router.recordedRequests
        XCTAssertEqual(requests.filter { $0.httpMethod == "POST" }.count, 0)
        XCTAssertEqual(requests.filter { $0.httpMethod == "GET" }.count, 2)
    }

    func testDoesNotFetchSameCandidateLyricsRepeatedly() async throws {
        let search = Data(#"{"result":{"songs":[{"id":7,"name":"Song","artists":[{"name":"Artist"}],"album":{"name":"Album"},"duration":180000}]}}"#.utf8)
        let noLyrics = Data(#"{"lrc":{"lyric":""}}"#.utf8)
        NetEaseURLProtocol.router.configure { request in
            if request.url?.path.contains("/api/song/lyric") == true {
                return (200, noLyrics)
            }
            return (200, search)
        }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = NetEaseLyricsClient(session: session, maxAutomaticSearches: 5)

        let snapshot = try await client.fetch(for: track)

        XCTAssertEqual(snapshot.availability, .notFound)
        let lyricRequests = NetEaseURLProtocol.router.recordedRequests.filter {
            $0.url?.path.contains("/api/song/lyric") == true
        }
        XCTAssertEqual(lyricRequests.count, 1)
    }

    func testSurfacesProviderOutageAfterGETAndPOSTFail() async {
        NetEaseURLProtocol.router.configure { _ in (503, Data()) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let client = NetEaseLyricsClient(session: session)

        do {
            _ = try await client.fetch(for: track)
            XCTFail("Expected NetEaseLyricsError")
        } catch let error as NetEaseLyricsError {
            XCTAssertEqual(error, .httpStatus(503))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetEaseURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private var track: Track {
        Track(
            id: "track",
            name: "Song",
            artist: "Artist",
            album: "Album",
            duration: 180,
            position: 0,
            isPlaying: true
        )
    }
}
