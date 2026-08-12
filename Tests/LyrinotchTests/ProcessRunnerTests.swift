import XCTest
@testable import LyrinotchCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesOutputAndExitStatus() async throws {
        let result = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", "hello"],
            timeout: 2
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hello")
        XCTAssertEqual(result.stderr, "")
    }

    func testTimesOutAndTerminatesProcess() async {
        let started = Date()
        do {
            _ = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                timeout: 0.1
            )
            XCTFail("Expected timeout")
        } catch let error as ProcessRunnerError {
            guard case .timedOut = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
}
