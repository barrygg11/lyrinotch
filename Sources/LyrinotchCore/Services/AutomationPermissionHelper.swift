import AppKit
import Foundation

/// Current macOS Automation (TCC) permission state for target music players.
public enum AutomationPermissionStatus: String, Sendable {
    case authorized
    case denied
    case notDetermined
    case unknown
    case playerNotRunning
    case timedOut
}

enum AutomationScriptProbeResult: Sendable, Equatable {
    case output(String)
    case timedOut
    case launchFailed
}

/// Target music player application for AppleScript automation.
public enum TargetPlayerApp: String, CaseIterable, Sendable, Identifiable {
    case appleMusic = "com.apple.Music"
    case spotify = "com.spotify.client"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }

    fileprivate var scriptingName: String {
        switch self {
        case .appleMusic: return "Music"
        case .spotify: return "Spotify"
        }
    }
}

/// Helper for checking / requesting macOS Automation permission
/// (System Settings → Privacy & Security → Automation).
///
/// **Important:** `AEDeterminePermissionToAutomateTarget` is intentionally **not**
/// used — it has been observed to hang indefinitely on some systems, which crashed
/// or froze Settings → System when probing on tab appear. Status is inferred from a
/// short-timeout `osascript` probe instead.
public enum AutomationPermissionHelper {

    /// Non-prompting availability probe. macOS does not expose a reliable passive
    /// Automation authorization check here, so an installed player's status remains
    /// `.unknown` until the user explicitly requests a permission check.
    /// Completes within ~1.5s; safe for UI.
    public static func status(for target: TargetPlayerApp) -> AutomationPermissionStatus {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.rawValue) != nil else {
            return .unknown
        }
        return softScriptProbe(for: target, askUserFacing: false)
    }

    /// Attempt to trigger / re-check permission (may show system dialog via osascript).
    @discardableResult
    public static func requestPermission(for target: TargetPlayerApp) -> AutomationPermissionStatus {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.rawValue) != nil else {
            return .unknown
        }
        // A real player property access is more likely to surface the TCC dialog.
        return softScriptProbe(for: target, askUserFacing: true)
    }

    /// Open macOS System Settings → Privacy & Security → Automation.
    public static func openSystemAutomationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    // MARK: - Private

    private static func softScriptProbe(
        for target: TargetPlayerApp,
        askUserFacing: Bool
    ) -> AutomationPermissionStatus {
        let app = target.scriptingName

        // Lightweight: only checks whether we may talk to the app.
        // askUserFacing=true uses a harmless property that can prompt TCC.
        let script: String
        if askUserFacing {
            script = """
            try
              if application "\(app)" is running then
                tell application "\(app)"
                  -- Accessing a property may prompt Automation if not determined.
                  set _ to player state
                  return "OK"
                end tell
              else
                return "NOT_RUNNING"
              end if
            on error errMsg number errNum
              return "ERR:" & errNum & ":" & errMsg
            end try
            """
        } else {
            script = """
            try
              if application "\(app)" is running then
                return "OK"
              else
                return "NOT_RUNNING"
              end if
            on error errMsg number errNum
              return "ERR:" & errNum & ":" & errMsg
            end try
            """
        }

        let timeout = askUserFacing ? 15.0 : 1.4
        let result = runOSAscript(script, timeoutSeconds: timeout)
        return status(fromProbeResult: result, askUserFacing: askUserFacing)
    }

    /// Converts an osascript result into a permission state without treating app
    /// liveness as proof of Automation authorization.
    static func status(
        fromProbeOutput output: String,
        askUserFacing: Bool
    ) -> AutomationPermissionStatus {
        status(fromProbeResult: .output(output), askUserFacing: askUserFacing)
    }

    static func status(
        fromProbeResult result: AutomationScriptProbeResult,
        askUserFacing: Bool
    ) -> AutomationPermissionStatus {
        let output: String
        switch result {
        case let .output(value):
            output = value
        case .timedOut:
            return .timedOut
        case .launchFailed:
            return .unknown
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == "OK" {
            return askUserFacing ? .authorized : .unknown
        }
        if trimmed == "NOT_RUNNING" {
            return .playerNotRunning
        }
        if trimmed == "PLAYER_RUNNING" {
            return .unknown
        }
        if trimmed.hasPrefix("ERR:") {
            let lower = trimmed.lowercased()
            if lower.contains("-1744") {
                return .notDetermined
            }
            if lower.contains("not allowed")
                || lower.contains("not authorised")
                || lower.contains("not authorized")
                || lower.contains("user has declined")
                || lower.contains("denied")
                || lower.contains("-1743")
                || lower.contains("1002")
            {
                return .denied
            }
            // -1728 errAENoSuchObject, app not scriptable until launched, etc.
            if lower.contains("-600")
                || lower.contains("not running")
                || lower.contains("connection is invalid")
            {
                return askUserFacing ? .playerNotRunning : .unknown
            }
            return .unknown
        }
        // Timeout / empty → don't block UI; unknown is fine.
        return .unknown
    }

    private static func runOSAscript(
        _ source: String,
        timeoutSeconds: TimeInterval
    ) -> AutomationScriptProbeResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return .launchFailed
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }
        let waitResult = group.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            process.terminate()
            // Drain briefly so the process can die without leaving zombies.
            _ = group.wait(timeout: .now() + 0.3)
            return .timedOut
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: data, encoding: .utf8) ?? ""
        if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .output(stdout)
        }
        return .output(String(data: errData, encoding: .utf8) ?? "")
    }
}
