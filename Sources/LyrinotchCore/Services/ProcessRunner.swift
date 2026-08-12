import Darwin
import Foundation

/// Result from a short-lived child process.
public struct ProcessResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum ProcessRunnerError: Error, Sendable, LocalizedError, Equatable {
    case timedOut(seconds: TimeInterval)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "Process timed out after \(String(format: "%.1f", seconds)) seconds"
        case .launchFailed(let message):
            return message
        }
    }
}

/// Runs Foundation `Process` without blocking an actor, drains both pipes while
/// the child is alive, and terminates the child on timeout or task cancellation.
public enum ProcessRunner {
    public static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        let state = ProcessState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: runBlocking(
                        executableURL: executableURL,
                        arguments: arguments,
                        timeout: max(0.1, timeout),
                        state: state
                    ))
                }
            }
        } onCancel: {
            state.cancel()
        }
    }

    private static func runBlocking(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        state: ProcessState
    ) -> Result<ProcessResult, Error> {
        if state.isCancelled {
            return .failure(CancellationError())
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .failure(ProcessRunnerError.launchFailed(error.localizedDescription))
        }
        state.install(process)

        let stdout = PipeBuffer()
        let stderr = PipeBuffer()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stdout.replace(with: stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stderr.replace(with: stderrPipe.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline, !state.isCancelled {
            Thread.sleep(forTimeInterval: 0.02)
        }

        let cancelled = state.isCancelled
        let timedOut = process.isRunning && !cancelled
        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(0.5)
            while process.isRunning, Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                process.interrupt()
            }
            let killDeadline = Date().addingTimeInterval(0.5)
            while process.isRunning, Date() < killDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        readers.wait()
        state.finish()

        if cancelled {
            return .failure(CancellationError())
        }
        if timedOut {
            return .failure(ProcessRunnerError.timedOut(seconds: timeout))
        }

        return .success(ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdout.string,
            stderr: stderr.string
        ))
    }
}

private final class ProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func install(_ process: Process) {
        let shouldTerminate = lock.withLock { () -> Bool in
            self.process = process
            return cancelled
        }
        if shouldTerminate, process.isRunning {
            process.terminate()
        }
    }

    func cancel() {
        let running = lock.withLock { () -> Process? in
            cancelled = true
            return process
        }
        if let running, running.isRunning {
            running.terminate()
        }
    }

    func finish() {
        lock.withLock { process = nil }
    }
}

private final class PipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func replace(with data: Data) {
        lock.withLock { self.data = data }
    }

    var string: String {
        lock.withLock { String(data: data, encoding: .utf8) ?? "" }
    }
}
