import XCTest
@testable import LyrinotchCore

private final class BoundedResponseBodyStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()

    func set(_ body: Data) { lock.withLock { value = body } }
    var body: Data { lock.withLock { value } }
}

private final class BoundedResponseURLProtocol: URLProtocol, @unchecked Sendable {
    static let store = BoundedResponseBodyStore()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.store.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class BoundedResponseLoaderTests: XCTestCase {
    func testRejectsBodyAfterMaximumBytes() async throws {
        BoundedResponseURLProtocol.store.set(Data(repeating: 0x41, count: 33))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedResponseURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        do {
            _ = try await BoundedResponseLoader.data(
                for: URLRequest(url: URL(string: "https://example.com/data")!),
                in: session,
                maximumBytes: 32
            )
            XCTFail("Expected bounded loader to reject oversized body")
        } catch let error as BoundedResponseError {
            XCTAssertEqual(error, .responseTooLarge(maximumBytes: 32))
        }
    }

    func testAcceptsBodyAtMaximumBytes() async throws {
        BoundedResponseURLProtocol.store.set(Data(repeating: 0x41, count: 32))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedResponseURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let result = try await BoundedResponseLoader.data(
            for: URLRequest(url: URL(string: "https://example.com/data")!),
            in: session,
            maximumBytes: 32
        )

        XCTAssertEqual(result.data.count, 32)
        XCTAssertEqual(result.response.statusCode, 200)
    }
}
