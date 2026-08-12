import AppKit
import CryptoKit
import Foundation
import LyrinotchCore

/// Checks GitHub Releases and can download + install the DMG asset in-place.
enum UpdateChecker {
    static let maximumUpdateDownloadBytes: Int64 = 512 * 1024 * 1024

    static func isUpdateDownloadSizeAllowed(_ bytes: Int64) -> Bool {
        bytes >= 0 && bytes <= maximumUpdateDownloadBytes
    }

    static func validateStagedAppResources(
        _ appURL: URL,
        maximumBytes: Int64 = maximumUpdateDownloadBytes * 2,
        maximumFiles: Int = 50_000
    ) -> String? {
        let fileManager = FileManager.default
        guard maximumBytes >= 0, maximumFiles >= 0 else {
            return "invalid staged app resource limits"
        }
        guard let rootValues = try? appURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              rootValues.isSymbolicLink != true,
              rootValues.isDirectory == true
        else { return "staged app is not a directory" }

        guard let enumerator = fileManager.enumerator(
            at: appURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .fileAllocatedSizeKey
            ],
            options: []
        ) else { return "could not enumerate staged app" }

        var fileCount = 0
        var totalBytes: Int64 = 0
        for case let itemURL as URL in enumerator {
            fileCount += 1
            guard fileCount <= maximumFiles else {
                return "staged app exceeds the file-count limit"
            }
            guard let values = try? itemURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .fileAllocatedSizeKey
            ]) else {
                return "could not inspect staged app resources"
            }
            if values.isSymbolicLink == true {
                return "staged app contains a symbolic link"
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                return "staged app contains a non-regular file"
            }
            guard let logicalSize = values.fileSize.map(Int64.init), logicalSize >= 0 else {
                return "could not inspect staged app file size"
            }
            let allocatedSize = values.fileAllocatedSize.map(Int64.init) ?? logicalSize
            guard allocatedSize >= 0 else {
                return "could not inspect staged app allocation size"
            }
            let bytes = max(logicalSize, allocatedSize)
            guard bytes >= 0,
                  bytes <= maximumBytes,
                  totalBytes <= maximumBytes - bytes
            else {
                return "staged app exceeds the expanded-size limit"
            }
            totalBytes += bytes
        }
        return nil
    }

    struct UpdateAsset: Equatable {
        var url: URL
        var sha256: String?
    }

    enum Outcome: Equatable {
        case notConfigured
        case upToDate(current: String, latest: String)
        /// Newer release; `asset` when a trusted GitHub `.dmg` asset is attached.
        case updateAvailable(current: String, latest: String, htmlURL: URL, asset: UpdateAsset?)
        case failed(message: String)
    }

    enum InstallOutcome: Equatable {
        case success
        case failed(message: String)
    }

    /// Query `GET /repos/{owner}/{repo}/releases/latest`.
    static func checkForUpdates() async -> Outcome {
        guard let repo = AppInfo.githubRepositoryPath else {
            return .notConfigured
        }

        let current = AppInfo.shortVersion
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return .failed(message: "Invalid GitHub API URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Lyrinotch/\(current) (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 404 {
                    return .failed(message: L10n.t("update.no_releases"))
                }
                guard (200..<300).contains(http.statusCode) else {
                    return .failed(message: L10n.t("update.http_error", http.statusCode))
                }
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestRaw = release.tagName
            let latest = ReleaseUpdatePolicy.normalizeVersion(latestRaw)
            let currentNorm = ReleaseUpdatePolicy.normalizeVersion(current)

            if ReleaseUpdatePolicy.compareVersions(latest, currentNorm) > 0 {
                let page = release.htmlURL.flatMap(URL.init(string:))
                    ?? URL(string: "\(AppInfo.repositoryURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/releases/latest")
                guard let page else {
                    return .failed(message: L10n.t("update.bad_release_url"))
                }
                let asset: UpdateAsset? = release.assets?
                    .first(where: { $0.name.lowercased().hasSuffix(".dmg") })
                    .flatMap { releaseAsset -> UpdateAsset? in
                        guard let url = URL(string: releaseAsset.browserDownloadURL),
                              ReleaseUpdatePolicy.isTrustedGitHubReleaseAssetURL(url, repositoryPath: repo)
                        else { return nil }
                        return UpdateAsset(
                            url: url,
                            sha256: ReleaseUpdatePolicy.normalizedSHA256(releaseAsset.digest)
                        )
                    }
                return .updateAvailable(
                    current: current,
                    latest: latestRaw,
                    htmlURL: page,
                    asset: asset
                )
            }
            return .upToDate(current: current, latest: latestRaw)
        } catch {
            return .failed(message: L10n.t("update.failed", error.localizedDescription))
        }
    }

    @discardableResult
    static func openReleasePage(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    /// Automatic replacement is available only for Developer ID builds configured
    /// with a trusted Team ID in the signed app bundle.
    static var canInstallAutomatically: Bool {
        AppInfo.expectedUpdateTeamIdentifier != nil
    }

    /// Download DMG, validate digest/signature/identity, stage next to the installed
    /// app, then ask the helper process to atomically replace it after termination.
    static func installUpdate(
        asset: UpdateAsset,
        expectedVersion: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> InstallOutcome {
        guard let expectedTeamID = AppInfo.expectedUpdateTeamIdentifier else {
            return .failed(message: L10n.t("update.secure_install_unavailable"))
        }
        guard let repo = AppInfo.githubRepositoryPath,
              ReleaseUpdatePolicy.isTrustedGitHubReleaseAssetURL(asset.url, repositoryPath: repo)
        else {
            return .failed(message: L10n.t("update.untrusted_download"))
        }
        let runningApp = Bundle.main.bundleURL
        guard runningApp.pathExtension == "app" else {
            return .failed(message: L10n.t("update.secure_install_unavailable"))
        }
        if let validationError = await validateDownloadedApp(
            runningApp,
            expectedVersion: AppInfo.shortVersion,
            expectedTeamID: expectedTeamID
        ) {
            return .failed(message: L10n.t(
                "update.validation_failed",
                "running app: \(validationError)"
            ))
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrinotch-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return .failed(message: L10n.t("update.install_failed", error.localizedDescription))
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dmgPath = tempDir.appendingPathComponent("update.dmg")
        do {
            let delegate = DownloadProgressDelegate(
                maximumBytes: maximumUpdateDownloadBytes,
                onProgress: progress
            )
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (bytes, response) = try await session.download(from: asset.url)
            session.invalidateAndCancel()
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failed(message: L10n.t("update.http_error", http.statusCode))
            }
            let downloadedSize = try bytes.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard !delegate.didExceedLimit,
                  let downloadedSize,
                  isUpdateDownloadSizeAllowed(Int64(downloadedSize))
            else {
                return .failed(message: L10n.t(
                    "update.download_failed",
                    "download exceeds the update size limit"
                ))
            }
            try? FileManager.default.removeItem(at: dmgPath)
            try FileManager.default.moveItem(at: bytes, to: dmgPath)
            if let expectedDigest = asset.sha256 {
                let actual = try sha256(of: dmgPath)
                guard actual.caseInsensitiveCompare(expectedDigest) == .orderedSame else {
                    return .failed(message: L10n.t("update.digest_mismatch"))
                }
            }
        } catch {
            return .failed(message: L10n.t("update.download_failed", error.localizedDescription))
        }

        progress?(0.85)

        // Mount DMG (read-only).
        let attach = await runProcess("/usr/bin/hdiutil", arguments: [
            "attach", dmgPath.path, "-nobrowse", "-readonly", "-plist"
        ])
        guard attach.exitCode == 0 else {
            return .failed(message: L10n.t("update.mount_failed", attach.stderr))
        }

        guard let mountPoint = mountPoint(fromHdiutilPlist: attach.stdout) else {
            return .failed(message: L10n.t("update.mount_failed", "no mount point"))
        }

        progress?(0.90)

        let sourceApp = URL(fileURLWithPath: mountPoint)
            .appendingPathComponent("Lyrinotch.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceApp.path) else {
            _ = await runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-force"])
            return .failed(message: L10n.t("update.no_app_in_dmg"))
        }
        if let resourceError = validateStagedAppResources(sourceApp) {
            _ = await runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-force"])
            return .failed(message: L10n.t("update.validation_failed", resourceError))
        }

        // Copy sourceApp to a persistent staging directory outside tempDir.
        let updateStageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrinotch-stage-\(UUID().uuidString)", isDirectory: true)
        let stagedApp = updateStageDir.appendingPathComponent("Lyrinotch.app", isDirectory: true)
        var handedOffToHelper = false
        defer {
            if !handedOffToHelper {
                try? FileManager.default.removeItem(at: updateStageDir)
            }
        }

        do {
            try FileManager.default.createDirectory(at: updateStageDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceApp, to: stagedApp)
        } catch {
            _ = await runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-force"])
            return .failed(message: L10n.t("update.install_failed", error.localizedDescription))
        }

        if let resourceError = validateStagedAppResources(stagedApp) {
            _ = await runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-force"])
            return .failed(message: L10n.t("update.validation_failed", resourceError))
        }

        // Unmount DMG.
        _ = await runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-force"])
        progress?(0.95)

        let destination = installDestinationURL()
        if let validationError = await validateDownloadedApp(
            stagedApp,
            expectedVersion: expectedVersion,
            expectedTeamID: expectedTeamID
        ) {
            try? FileManager.default.removeItem(at: updateStageDir)
            return .failed(message: L10n.t("update.validation_failed", validationError))
        }

        // Pre-copy to the destination volume before terminating. If permissions or
        // disk space are insufficient, the running app remains untouched.
        let incomingApp = destination.deletingLastPathComponent()
            .appendingPathComponent(".Lyrinotch.update-\(UUID().uuidString).app", isDirectory: true)
        do {
            try FileManager.default.copyItem(at: stagedApp, to: incomingApp)
        } catch {
            try? FileManager.default.removeItem(at: incomingApp)
            try? FileManager.default.removeItem(at: updateStageDir)
            return .failed(message: L10n.t("update.install_failed", error.localizedDescription))
        }

        // Launch the current executable as a detached helper. Arguments are passed
        // directly—no shell parsing or path interpolation is involved.
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = Bundle.main.executableURL
        process.arguments = [
            "--apply-update",
            "--parent-pid", String(pid),
            "--incoming-app", incomingApp.path,
            "--destination-app", destination.path,
            "--cleanup-directory", updateStageDir.path
        ]
        do {
            try process.run()
            handedOffToHelper = true
        } catch {
            try? FileManager.default.removeItem(at: incomingApp)
            try? FileManager.default.removeItem(at: updateStageDir)
            return .failed(message: L10n.t("update.install_failed", error.localizedDescription))
        }

        progress?(1.0)

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
        return .success
    }

    /// Prefer replacing the running .app; fall back to /Applications/Lyrinotch.app.
    private static func installDestinationURL() -> URL {
        let running = Bundle.main.bundleURL
        if running.pathExtension == "app" {
            return running
        }
        return URL(fileURLWithPath: "/Applications/Lyrinotch.app")
    }

    private static func mountPoint(fromHdiutilPlist xml: String) -> String? {
        guard let data = xml.data(using: .utf8) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]]
        else { return nil }
        for entity in entities {
            if let mp = entity["mount-point"] as? String, !mp.isEmpty {
                return mp
            }
        }
        return nil
    }

    private static func runProcess(_ launchPath: String, arguments: [String]) async -> ProcessResult {
        do {
            return try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: launchPath),
                arguments: arguments,
                timeout: 30
            )
        } catch {
            return ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
    }

    private static func validateDownloadedApp(
        _ appURL: URL,
        expectedVersion: String,
        expectedTeamID: String
    ) async -> String? {
        guard let bundle = Bundle(url: appURL) else { return "invalid app bundle" }
        guard bundle.bundleIdentifier == AppInfo.bundleIdentifier else {
            return "bundle identifier mismatch"
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard ReleaseUpdatePolicy.normalizeVersion(version)
                == ReleaseUpdatePolicy.normalizeVersion(expectedVersion)
        else {
            return "version mismatch"
        }

        let verify = await runProcess("/usr/bin/codesign", arguments: [
            "--verify", "--deep", "--strict", "--verbose=2", appURL.path
        ])
        guard verify.exitCode == 0 else {
            return verify.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let detail = await runProcess("/usr/bin/codesign", arguments: [
            "-d", "--verbose=4", appURL.path
        ])
        let metadata = detail.stdout + "\n" + detail.stderr
        let teamID = String(metadata
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("TeamIdentifier=") })?
            .dropFirst("TeamIdentifier=".count) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard teamID == expectedTeamID else { return "Developer Team ID mismatch" }
        return nil
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

}

// MARK: - Download progress delegate

/// Tracks download progress via URLSession delegate and reports 0.0–0.8 range
/// (reserving 0.8–1.0 for mount/copy/relaunch).
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let maximumBytes: Int64
    private let onProgress: (@Sendable (Double) -> Void)?
    private let lock = NSLock()
    private var exceededLimit = false

    init(maximumBytes: Int64, onProgress: (@Sendable (Double) -> Void)?) {
        self.maximumBytes = maximumBytes
        self.onProgress = onProgress
    }

    var didExceedLimit: Bool { lock.withLock { exceededLimit } }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > maximumBytes || totalBytesWritten > maximumBytes {
            lock.withLock { exceededLimit = true }
            downloadTask.cancel()
            return
        }
        guard totalBytesExpectedToWrite > 0 else { return }
        // Map download progress to 0.0–0.8 range.
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress?(min(fraction * 0.8, 0.8))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Handled by the async download(from:) call.
    }
}

// MARK: - GitHub JSON

private struct GitHubRelease: Decodable {
    var tagName: String
    var htmlURL: String?
    var assets: [GitHubAsset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    var name: String
    var browserDownloadURL: String
    var digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

// MARK: - AppInfo helpers

extension AppInfo {
    static var githubRepositoryPath: String? {
        let raw = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw),
              let host = url.host?.lowercased(),
              host == "github.com" || host == "www.github.com"
        else { return nil }

        let parts = url.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    static var canCheckForUpdates: Bool {
        githubRepositoryPath != nil
    }
}
