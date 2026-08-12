import XCTest
@testable import LyrinotchCore

final class UpdateVersionTests: XCTestCase {
    func testNormalizeStripsV() {
        XCTAssertEqual(ReleaseUpdatePolicy.normalizeVersion("v1.2.3"), "1.2.3")
        XCTAssertEqual(ReleaseUpdatePolicy.normalizeVersion("V2.0"), "2.0")
        XCTAssertEqual(ReleaseUpdatePolicy.normalizeVersion("1.0.0-beta"), "1.0.0")
    }

    func testCompare() {
        XCTAssertEqual(ReleaseUpdatePolicy.compareVersions("1.0.0", "1.0.0"), 0)
        XCTAssertTrue(ReleaseUpdatePolicy.compareVersions("1.0.1", "1.0.0") > 0)
        XCTAssertTrue(ReleaseUpdatePolicy.compareVersions("1.0.0", "1.0.1") < 0)
        XCTAssertTrue(ReleaseUpdatePolicy.compareVersions("2.0", "1.9.9") > 0)
        XCTAssertTrue(ReleaseUpdatePolicy.compareVersions("1.0", "1.0.0") == 0)
    }

    func testOnlyTrustsThisRepositoriesHTTPSReleaseAssets() throws {
        let trusted = try XCTUnwrap(URL(
            string: "https://github.com/acme/lyrinotch/releases/download/v1.2/Lyrinotch.dmg"
        ))
        XCTAssertTrue(ReleaseUpdatePolicy.isTrustedGitHubReleaseAssetURL(
            trusted,
            repositoryPath: "acme/lyrinotch"
        ))

        for raw in [
            "http://github.com/acme/lyrinotch/releases/download/v1.2/Lyrinotch.dmg",
            "https://github.com.evil.example/acme/lyrinotch/releases/download/v1.2/Lyrinotch.dmg",
            "https://github.com/acme/other/releases/download/v1.2/Lyrinotch.dmg"
        ] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertFalse(ReleaseUpdatePolicy.isTrustedGitHubReleaseAssetURL(
                url,
                repositoryPath: "acme/lyrinotch"
            ))
        }
    }

    func testNormalizesGitHubDigest() {
        let digest = String(repeating: "aB", count: 32)
        XCTAssertEqual(
            ReleaseUpdatePolicy.normalizedSHA256("sha256:\(digest)"),
            digest.lowercased()
        )
        XCTAssertNil(ReleaseUpdatePolicy.normalizedSHA256("sha256:not-a-digest"))
    }
}
