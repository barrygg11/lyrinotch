import XCTest
@testable import Lyrinotch

final class UpdateResourceLimitTests: XCTestCase {
    func testDownloadLimitIsFiniteAndRejectsOneByteOverMaximum() {
        XCTAssertGreaterThan(UpdateChecker.maximumUpdateDownloadBytes, 0)
        XCTAssertTrue(UpdateChecker.isUpdateDownloadSizeAllowed(UpdateChecker.maximumUpdateDownloadBytes))
        XCTAssertFalse(UpdateChecker.isUpdateDownloadSizeAllowed(UpdateChecker.maximumUpdateDownloadBytes + 1))
    }

    func testExpandedAppResourceLimitsRejectOversizedTree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrinotch-resource-limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Lyrinotch.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let payload = app.appendingPathComponent("payload.bin")
        try Data(repeating: 0x41, count: 1_024).write(to: payload)

        let result = UpdateChecker.validateStagedAppResources(
            app,
            maximumBytes: 512,
            maximumFiles: 10
        )

        XCTAssertNotNil(result)
    }

    func testExpandedAppResourceLimitsRejectSymlinks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrinotch-resource-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Lyrinotch.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: app.appendingPathComponent("link"),
            withDestinationURL: target
        )

        XCTAssertNotNil(UpdateChecker.validateStagedAppResources(app))
    }
}
