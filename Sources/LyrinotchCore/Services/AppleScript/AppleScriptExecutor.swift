import Foundation

/// Runs AppleScript source and returns stdout text.
public protocol AppleScriptExecuting: Sendable {
    func run(script: String) async throws -> String
}

/// Backward-compatible alias used by older Spotify-only call sites / tests.
public typealias SpotifyScriptExecuting = AppleScriptExecuting

public enum AppleScriptError: Error, Equatable, Sendable, LocalizedError {
    case osascriptNotFound
    case nonZeroExit(status: Int32, stderr: String)
    case emptyOutput
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .osascriptNotFound:
            return "osascript not found at /usr/bin/osascript"
        case .nonZeroExit(let status, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "osascript exited with status \(status)"
            }
            return "osascript failed (\(status)): \(trimmed)"
        case .emptyOutput:
            return "osascript returned empty output"
        case .timedOut:
            return "osascript timed out"
        }
    }
}

/// Historical name used in tests.
public typealias SpotifyScriptError = AppleScriptError

/// Default executor: `/usr/bin/osascript` via `Process`.
public struct ProcessAppleScriptExecutor: AppleScriptExecuting {
    public init() {}

    public func run(script: String) async throws -> String {
        let osascript = URL(fileURLWithPath: "/usr/bin/osascript")
        guard FileManager.default.isExecutableFile(atPath: osascript.path) else {
            throw AppleScriptError.osascriptNotFound
        }
        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(
                executableURL: osascript,
                arguments: ["-e", script],
                timeout: 4
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ProcessRunnerError {
            if case .timedOut = error { throw AppleScriptError.timedOut }
            throw error
        }

        let outText = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode != 0 {
            throw AppleScriptError.nonZeroExit(
                status: result.exitCode,
                stderr: result.stderr
            )
        }

        if outText.isEmpty {
            throw AppleScriptError.emptyOutput
        }

        return outText
    }
}

/// Historical name used by Spotify-only services/tests.
public typealias ProcessSpotifyScriptExecutor = ProcessAppleScriptExecutor
