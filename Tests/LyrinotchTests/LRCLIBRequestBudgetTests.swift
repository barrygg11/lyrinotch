import XCTest
@testable import LyrinotchCore

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func reset() { lock.withLock { value = 0 } }
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

private final class NotFoundURLProtocol: URLProtocol, @unchecked Sendable {
    static let counter = RequestCounter()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.counter.increment()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class MalformedDurationURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Data(#"{"id":1,"trackName":"Song","artistName":"Artist","duration":1e300,"plainLyrics":"line"}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LRCLIBRequestBudgetTests: XCTestCase {
    func testAutomaticLookupNeverExceedsRequestBudget() async throws {
        NotFoundURLProtocol.counter.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NotFoundURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = LRCLIBClient(session: session, maxAutomaticRequests: 8)
        let track = Track(
            id: nil,
            name: "後來的我們（現場版）",
            artist: "五月天 Mayday",
            album: "自傳",
            duration: 350,
            position: 100,
            isPlaying: true
        )

        let result = try await client.fetch(for: track)

        XCTAssertEqual(result.availability, .notFound)
        XCTAssertGreaterThan(NotFoundURLProtocol.counter.count, 0)
        XCTAssertLessThanOrEqual(NotFoundURLProtocol.counter.count, 8)
    }

    func testUnrepresentableProviderDurationIsIgnored() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MalformedDurationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = LRCLIBClient(session: session, maxAutomaticRequests: 1)
        let track = Track(
            id: "track",
            name: "Song",
            artist: "Artist",
            album: nil,
            duration: 180,
            position: 0,
            isPlaying: true
        )

        let result = try await client.fetch(for: track)

        XCTAssertEqual(result.availability, .plain)
        XCTAssertNil(result.matchedTrack?.duration)
    }
}
