import Foundation
import XCTest
@testable import Lyrinotch

final class UpdateInstallerHelperTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Applications")

    func testFailedMoveRestoresPreviousApp() {
        let urls = makeURLs()
        let operations = FakeUpdateInstallerOperations(
            existing: [urls.incoming, urls.destination, urls.cleanup],
            moveFailures: [.init(source: urls.incoming, destination: urls.destination)]
        )

        let outcome = UpdateInstallerHelper.apply(
            incoming: urls.incoming,
            destination: urls.destination,
            cleanup: urls.cleanup,
            operations: operations,
            backupURL: urls.backup
        )

        XCTAssertEqual(outcome.status, .restoredPreviousApp)
        XCTAssertEqual(outcome.reopenedApplication, urls.destination)
        XCTAssertNil(outcome.preservedBackup)
        XCTAssertTrue(operations.itemExists(at: urls.destination))
        XCTAssertTrue(operations.itemExists(at: urls.incoming))
        XCTAssertTrue(operations.itemExists(at: urls.cleanup))
    }

    func testFailedRollbackPreservesBackup() {
        let urls = makeURLs()
        let operations = FakeUpdateInstallerOperations(
            existing: [urls.incoming, urls.destination, urls.cleanup],
            moveFailures: [
                .init(source: urls.incoming, destination: urls.destination),
                .init(source: urls.backup, destination: urls.destination)
            ]
        )

        let outcome = UpdateInstallerHelper.apply(
            incoming: urls.incoming,
            destination: urls.destination,
            cleanup: urls.cleanup,
            operations: operations,
            backupURL: urls.backup
        )

        XCTAssertEqual(outcome.status, .recoveryRequired)
        XCTAssertEqual(outcome.preservedBackup, urls.backup)
        XCTAssertEqual(outcome.reopenedApplication, urls.backup)
        XCTAssertEqual(outcome.detail?.contains("Rollback also failed"), true)
        XCTAssertTrue(operations.itemExists(at: urls.backup))
        XCTAssertTrue(operations.itemExists(at: urls.incoming))
        XCTAssertTrue(operations.itemExists(at: urls.cleanup))
    }

    func testLaunchFailurePreservesCandidateAndRestoresPreviousApp() {
        let urls = makeURLs()
        let operations = FakeUpdateInstallerOperations(
            existing: [urls.incoming, urls.destination, urls.cleanup],
            openResults: [urls.destination: [false, true]]
        )

        let outcome = UpdateInstallerHelper.apply(
            incoming: urls.incoming,
            destination: urls.destination,
            cleanup: urls.cleanup,
            operations: operations,
            backupURL: urls.backup
        )

        XCTAssertEqual(outcome.status, .restoredPreviousApp)
        XCTAssertEqual(outcome.reopenedApplication, urls.destination)
        XCTAssertTrue(operations.itemExists(at: urls.destination))
        XCTAssertTrue(operations.itemExists(at: urls.incoming))
        XCTAssertTrue(operations.itemExists(at: urls.cleanup))
    }

    func testSuccessfulInstallCleansUp() {
        let urls = makeURLs()
        let operations = FakeUpdateInstallerOperations(
            existing: [urls.incoming, urls.destination, urls.cleanup]
        )

        let outcome = UpdateInstallerHelper.apply(
            incoming: urls.incoming,
            destination: urls.destination,
            cleanup: urls.cleanup,
            operations: operations,
            backupURL: urls.backup
        )

        XCTAssertEqual(outcome.status, .installed)
        XCTAssertEqual(outcome.reopenedApplication, urls.destination)
        XCTAssertFalse(operations.itemExists(at: urls.backup))
        XCTAssertFalse(operations.itemExists(at: urls.incoming))
        XCTAssertFalse(operations.itemExists(at: urls.cleanup))
        XCTAssertTrue(operations.itemExists(at: urls.destination))
    }

    private func makeURLs() -> (
        incoming: URL,
        destination: URL,
        cleanup: URL,
        backup: URL
    ) {
        (
            incoming: root.appendingPathComponent(".Lyrinotch.update-test.app"),
            destination: root.appendingPathComponent("Lyrinotch.app"),
            cleanup: URL(fileURLWithPath: "/tmp/lyrinotch-stage-test"),
            backup: root.appendingPathComponent(".Lyrinotch.backup-test.app")
        )
    }
}

private final class FakeUpdateInstallerOperations: UpdateInstallerOperating {
    struct Move: Hashable {
        let source: URL
        let destination: URL
    }

    private(set) var existing: Set<URL>
    private let moveFailures: Set<Move>
    private var openResults: [URL: [Bool]]

    init(
        existing: Set<URL>,
        moveFailures: Set<Move> = [],
        openResults: [URL: [Bool]] = [:]
    ) {
        self.existing = existing
        self.moveFailures = moveFailures
        self.openResults = openResults
    }

    func itemExists(at url: URL) -> Bool {
        existing.contains(url)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        if moveFailures.contains(.init(source: source, destination: destination)) {
            throw FakeError.moveFailed
        }
        guard existing.contains(source), !existing.contains(destination) else {
            throw FakeError.invalidMove
        }
        existing.remove(source)
        existing.insert(destination)
    }

    func removeItem(at url: URL) throws {
        guard existing.remove(url) != nil else {
            throw FakeError.missingItem
        }
    }

    func openApplication(at url: URL) -> Bool {
        guard existing.contains(url) else { return false }
        guard var results = openResults[url], !results.isEmpty else { return true }
        let result = results.removeFirst()
        openResults[url] = results
        return result
    }

    private enum FakeError: Error {
        case moveFailed
        case invalidMove
        case missingItem
    }
}
