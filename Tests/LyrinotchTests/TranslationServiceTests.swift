import XCTest
@testable import LyrinotchCore

private final class TranslationURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var lastRequestURL: URL?
    private static let lock = NSLock()

    static func reset() {
        lock.withLock {
            responseData = Data(#"{"responseData":{"translatedText":"你好"}}"#.utf8)
            statusCode = 200
            requestCount = 0
            lastRequestURL = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let snapshot = Self.lock.withLock { () -> (Data, Int) in
            Self.requestCount += 1
            Self.lastRequestURL = request.url
            return (Self.responseData, Self.statusCode)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: snapshot.1,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "application/json",
                "Content-Length": String(snapshot.0.count)
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: snapshot.0)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class TranslationServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TranslationURLProtocol.reset()
    }

    func testTranslationUsesExpectedHTTPSQuery() async {
        let service = TranslationService(session: makeSession())

        let translated = await service.translate("Hello world", to: "zh-TW")

        XCTAssertEqual(translated, "你好")
        let components = TranslationURLProtocol.lastRequestURL
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        XCTAssertEqual(components?.scheme, "https")
        XCTAssertEqual(queryValue("q", in: components), "Hello world")
        XCTAssertEqual(queryValue("langpair", in: components), "en|zh-TW")
    }

    func testCacheCanBeExplicitlyCleared() async {
        let service = TranslationService(session: makeSession())

        _ = await service.translate("Hello world", to: "zh-TW")
        _ = await service.translate("Hello world", to: "zh-TW")
        XCTAssertEqual(TranslationURLProtocol.requestCount, 1)

        await service.clearCache()
        _ = await service.translate("Hello world", to: "zh-TW")
        XCTAssertEqual(TranslationURLProtocol.requestCount, 2)
    }

    func testSameLanguageAndInvalidTargetDoNotSendLyrics() async {
        let service = TranslationService(session: makeSession())

        let sameLanguage = await service.translate("中文歌詞", to: "zh-TW")
        let invalidTarget = await service.translate("Private lyric", to: "en|zh-TW")

        XCTAssertNil(sameLanguage)
        XCTAssertNil(invalidTarget)
        XCTAssertEqual(TranslationURLProtocol.requestCount, 0)
    }

    func testOversizedResponseIsRejected() async {
        TranslationURLProtocol.responseData = Data(repeating: 0x41, count: 64)
        let service = TranslationService(
            session: makeSession(),
            maximumResponseBytes: 32
        )

        let translated = await service.translate("Hello world", to: "zh-TW")

        XCTAssertNil(translated)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func queryValue(
        _ name: String,
        in components: URLComponents?
    ) -> String? {
        components?.queryItems?.first(where: { $0.name == name })?.value
    }
}
