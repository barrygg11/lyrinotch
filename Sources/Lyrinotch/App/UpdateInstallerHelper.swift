import AppKit
import Darwin
import Foundation

protocol UpdateInstallerOperating {
    func itemExists(at url: URL) -> Bool
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
    func openApplication(at url: URL) -> Bool
}

struct LiveUpdateInstallerOperations: UpdateInstallerOperating {
    private let fileManager = FileManager.default

    func itemExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try fileManager.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func openApplication(at url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

struct UpdateInstallerApplyOutcome: Equatable {
    enum Status: Equatable {
        case installed
        case restoredPreviousApp
        case recoveryRequired
    }

    let status: Status
    let detail: String?
    let preservedBackup: URL?
    let reopenedApplication: URL?
}

/// Hidden helper mode launched from the current executable after a verified update
/// has already been copied beside the installed app.
enum UpdateInstallerHelper {
    static func runIfRequested(arguments: [String]) -> Bool {
        guard arguments.contains("--apply-update") else { return false }
        let options = parsedOptions(arguments)
        guard let pidRaw = options["--parent-pid"], let parentPID = Int32(pidRaw), parentPID > 1,
              let incomingRaw = options["--incoming-app"],
              let destinationRaw = options["--destination-app"],
              let cleanupRaw = options["--cleanup-directory"]
        else {
            report("Update helper received incomplete arguments.", cleanup: nil)
            return true
        }

        let incoming = URL(fileURLWithPath: incomingRaw).standardizedFileURL
        let destination = URL(fileURLWithPath: destinationRaw).standardizedFileURL
        let cleanup = URL(fileURLWithPath: cleanupRaw).standardizedFileURL
        guard isSafe(incoming: incoming, destination: destination, cleanup: cleanup) else {
            report("Update helper rejected unsafe paths.", cleanup: nil)
            return true
        }

        guard waitForExit(pid: parentPID, timeout: 30) else {
            // Keep both the verified candidate and staging directory. Deleting them
            // here makes a transient timeout impossible to diagnose or recover from.
            report(
                "Timed out waiting for the running app to exit; update artifacts were preserved.",
                cleanup: cleanup
            )
            return true
        }

        let outcome = apply(incoming: incoming, destination: destination, cleanup: cleanup)
        if let detail = outcome.detail {
            // `report` writes into the staging directory only when it still exists.
            // This also makes a cleanup warning persistent instead of stderr-only.
            report(detail, cleanup: cleanup)
        }
        return true
    }

    private static func parsedOptions(_ arguments: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index + 1 < arguments.count {
            let key = arguments[index]
            if key.hasPrefix("--"), !arguments[index + 1].hasPrefix("--") {
                result[key] = arguments[index + 1]
                index += 2
            } else {
                index += 1
            }
        }
        return result
    }

    private static func isSafe(incoming: URL, destination: URL, cleanup: URL) -> Bool {
        guard incoming.pathExtension == "app", destination.pathExtension == "app",
              destination.lastPathComponent == "Lyrinotch.app",
              incoming.lastPathComponent.hasPrefix(".Lyrinotch.update-"),
              incoming.deletingLastPathComponent() == destination.deletingLastPathComponent()
        else { return false }

        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
        return cleanup.deletingLastPathComponent() == temporary
            && cleanup.lastPathComponent.hasPrefix("lyrinotch-stage-")
    }

    private static func waitForExit(pid: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 {
                return errno == ESRCH
            }
            usleep(100_000)
        }
        return kill(pid, 0) != 0 && errno == ESRCH
    }

    /// Applies a staged update using injectable operations so every failure and
    /// rollback branch can be exercised without touching an installed app.
    static func apply(
        incoming: URL,
        destination: URL,
        cleanup: URL,
        operations: any UpdateInstallerOperating = LiveUpdateInstallerOperations(),
        backupURL: URL? = nil
    ) -> UpdateInstallerApplyOutcome {
        let parent = destination.deletingLastPathComponent()
        let backup = backupURL ?? parent.appendingPathComponent(
            ".Lyrinotch.backup-\(UUID().uuidString).app",
            isDirectory: true
        )
        var movedPreviousApp = false

        if operations.itemExists(at: destination) {
            do {
                try operations.moveItem(at: destination, to: backup)
                movedPreviousApp = true
            } catch {
                let reopened = operations.openApplication(at: destination)
                return UpdateInstallerApplyOutcome(
                    status: reopened ? .restoredPreviousApp : .recoveryRequired,
                    detail: "Could not preserve the installed app before updating: \(error.localizedDescription). "
                        + (reopened
                            ? "The previous app was reopened; update artifacts were preserved."
                            : "The previous app could not be reopened; update artifacts were preserved."),
                    preservedBackup: operations.itemExists(at: backup) ? backup : nil,
                    reopenedApplication: reopened ? destination : nil
                )
            }
        }

        do {
            try operations.moveItem(at: incoming, to: destination)
        } catch {
            return restorePreviousApp(
                after: "Could not move the verified update into place: \(error.localizedDescription).",
                movedPreviousApp: movedPreviousApp,
                destination: destination,
                backup: backup,
                operations: operations
            )
        }

        guard operations.openApplication(at: destination) else {
            return restoreAfterLaunchFailure(
                movedPreviousApp: movedPreviousApp,
                incoming: incoming,
                destination: destination,
                backup: backup,
                operations: operations
            )
        }

        var warnings: [String] = []
        var preservedBackup: URL?
        if movedPreviousApp {
            do {
                try operations.removeItem(at: backup)
            } catch {
                preservedBackup = operations.itemExists(at: backup) ? backup : nil
                warnings.append("The update opened, but its backup could not be removed: \(error.localizedDescription).")
            }
        }
        do {
            try operations.removeItem(at: cleanup)
        } catch {
            warnings.append("The update opened, but its staging directory could not be removed: \(error.localizedDescription).")
        }

        return UpdateInstallerApplyOutcome(
            status: .installed,
            detail: warnings.isEmpty ? nil : warnings.joined(separator: " "),
            preservedBackup: preservedBackup,
            reopenedApplication: destination
        )
    }

    private static func restoreAfterLaunchFailure(
        movedPreviousApp: Bool,
        incoming: URL,
        destination: URL,
        backup: URL,
        operations: any UpdateInstallerOperating
    ) -> UpdateInstallerApplyOutcome {
        let launchFailure = "The installed update could not be opened."

        // Move the rejected candidate back to its hidden incoming path before
        // restoring the old app. This preserves both versions for diagnosis.
        do {
            try operations.moveItem(at: destination, to: incoming)
        } catch {
            let fallback = movedPreviousApp && operations.openApplication(at: backup)
            return UpdateInstallerApplyOutcome(
                status: .recoveryRequired,
                detail: "\(launchFailure) The failed candidate could not be preserved: "
                    + "\(error.localizedDescription). "
                    + (fallback
                        ? "The previous app was opened directly from its backup."
                        : "The previous app could not be reopened; both on-disk apps were left untouched."),
                preservedBackup: operations.itemExists(at: backup) ? backup : nil,
                reopenedApplication: fallback ? backup : nil
            )
        }

        return restorePreviousApp(
            after: launchFailure,
            movedPreviousApp: movedPreviousApp,
            destination: destination,
            backup: backup,
            operations: operations
        )
    }

    private static func restorePreviousApp(
        after primaryFailure: String,
        movedPreviousApp: Bool,
        destination: URL,
        backup: URL,
        operations: any UpdateInstallerOperating
    ) -> UpdateInstallerApplyOutcome {
        guard movedPreviousApp else {
            return UpdateInstallerApplyOutcome(
                status: .recoveryRequired,
                detail: "\(primaryFailure) There was no previous installed app to restore; "
                    + "the update artifacts were preserved.",
                preservedBackup: nil,
                reopenedApplication: nil
            )
        }

        do {
            try operations.moveItem(at: backup, to: destination)
        } catch {
            // A failed rollback must never be swallowed or followed by cleanup.
            // The backup stays at a known path and is launched directly if possible.
            let reopenedBackup = operations.openApplication(at: backup)
            return UpdateInstallerApplyOutcome(
                status: .recoveryRequired,
                detail: "\(primaryFailure) Rollback also failed: \(error.localizedDescription). "
                    + (reopenedBackup
                        ? "The previous app was opened directly from its preserved backup."
                        : "The preserved backup could not be opened automatically."),
                preservedBackup: operations.itemExists(at: backup) ? backup : nil,
                reopenedApplication: reopenedBackup ? backup : nil
            )
        }

        let reopenedPrevious = operations.openApplication(at: destination)
        return UpdateInstallerApplyOutcome(
            status: reopenedPrevious ? .restoredPreviousApp : .recoveryRequired,
            detail: "\(primaryFailure) "
                + (reopenedPrevious
                    ? "The previous app was restored and reopened; update artifacts were preserved."
                    : "The previous app was restored but could not be reopened; update artifacts were preserved."),
            preservedBackup: nil,
            reopenedApplication: reopenedPrevious ? destination : nil
        )
    }

    private static func report(_ message: String, cleanup: URL?) {
        let line = "Lyrinotch update helper: \(message)\n"
        if let data = line.data(using: .utf8) {
            try? FileHandle.standardError.write(contentsOf: data)
            if let cleanup, FileManager.default.fileExists(atPath: cleanup.path) {
                let diagnostics = cleanup.appendingPathComponent("update-install-error.txt")
                try? data.write(to: diagnostics, options: .atomic)
            }
        }
    }
}
