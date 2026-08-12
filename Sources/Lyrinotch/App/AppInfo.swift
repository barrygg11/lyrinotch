import AppKit
import Foundation
import LyrinotchCore

/// Marketing / about / support metadata (About + Support windows).
enum AppInfo {
    /// Display name in About / Support.
    static let maintainer = "barry"

    /// Soft copy for About / Support — not a paywall.
    static var donateBlurb: String { L10n.t("support.blurb") }

    /// Public release channel.
    static let releaseChannel = "Release"

    // MARK: - Public repository
    //
    // After you create the GitHub repo, set `repositoryURL` to the canonical page
    // (no trailing slash), e.g. "https://github.com/yourname/lyrinotch".
    // Issues / “Report a problem” use that base when set.

    /// Canonical GitHub (or other) project URL.
    static let repositoryURL = "https://github.com/barrygg11/lyrinotch"

    /// Developer Team ID trusted for in-app replacement. The packaging script writes
    /// this key only for Developer ID builds. Ad-hoc builds intentionally return nil
    /// and can update only through the release download page.
    static var expectedUpdateTeamIdentifier: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "LyrinotchUpdateTeamIdentifier") as? String
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    // MARK: - Support links (Stats-style multi-channel)
    //
    // Leave a string empty to hide that button. Paste full https:// URLs when ready:
    //   paypal / koFi / githubSponsors / patreon / website

    static let paypalURL = ""
    static let koFiURL = "https://ko-fi.com/barrylai"
    static let githubSponsorsURL = ""
    static let patreonURL = ""
    static let websiteURL = ""

    // MARK: - Bug report destinations
    //
    // Priority: explicit `bugReportURL` → `repositoryURL` + /issues/new → mailto → copy diagnostics.

    /// Explicit Issues / form URL. Empty = derive from `repositoryURL` when set.
    private static let bugReportURLOverride = ""

    /// Support inbox for `mailto:`. Empty = skip mail destination.
    static let supportEmail = "barry.lai@icloud.com"

    /// Effective web destination for “Report a problem…”.
    static var bugReportURL: String {
        let override = bugReportURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }
        let repo = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !repo.isEmpty else { return "" }
        return "\(repo)/issues/new"
    }

    /// Channels with a non-empty URL, in display order (mirrors Stats: multi-option row).
    static var enabledSupportChannels: [SupportChannel] {
        SupportChannel.allCases.filter { $0.url != nil }
    }

    static var hasAnySupportLink: Bool {
        !enabledSupportChannels.isEmpty
    }

    /// Always offer the button; destination may be URL, mail, or copy-only.
    static var hasBugReportAction: Bool { true }

    static var hasConfiguredBugReportDestination: Bool {
        !bugReportURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !supportEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// `CFBundleShortVersionString` (e.g. 1.0.0), with a safe default for `swift run`.
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.0"
    }

    /// `CFBundleVersion` build number (always a string for display).
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// e.g. `1.0.0 (1)` — marketing + build, standard for support tickets.
    static var versionWithBuild: String {
        "\(shortVersion) (\(buildNumber))"
    }

    /// Hero subtitle under the app name.
    static var versionLine: String {
        L10n.t("about.version_line", versionWithBuild)
    }

    /// `LSMinimumSystemVersion` from Info.plist.
    static var minimumSystemVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "14.0"
    }

    static var minimumSystemLine: String {
        "macOS \(minimumSystemVersion)+"
    }

    static var copyrightLine: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © \(Calendar.current.component(.year, from: Date())) \(maintainer)."
    }

    /// Running CPU architecture (arm64 / x86_64).
    static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "unknown"
        #endif
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "app.lyrinotch.Lyrinotch"
    }

    /// Multi-line blurb for “Copy version info” / bug reports.
    static var diagnosticsText: String {
        """
        Lyrinotch \(versionWithBuild)
        Channel: \(releaseChannel)
        Maintainer: \(maintainer)
        Bundle ID: \(bundleIdentifier)
        Minimum OS: \(minimumSystemLine)
        Architecture: \(architecture)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Language: \(L10n.current.resolved.rawValue)

        \(AppDiagnostics.shared.recentText())
        """
    }

    /// Pre-filled issue / mail template.
    ///
    /// - **Fill-in headings** (what / steps / expected): follow the user’s UI language
    ///   so they know what to write.
    /// - **Subject + diagnostics block**: always English for maintainer triage and
    ///   consistent GitHub Issues / mail search.
    static var bugReportTemplateBody: String {
        """
        ## \(L10n.t("bug.what_happened"))


        ## \(L10n.t("bug.steps"))


        ## \(L10n.t("bug.expected"))


        ---
        ### Diagnostics (please keep)
        \(diagnosticsText)
        """
    }

    /// Always English (not localized) for sorting and search.
    static var bugReportSubject: String {
        "Lyrinotch \(versionWithBuild) — bug report"
    }

    @discardableResult
    static func copyDiagnosticsToPasteboard() -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setString(diagnosticsText, forType: .string)
    }

    /// Result of tapping “Report a problem”.
    enum BugReportOutcome: Equatable {
        /// Opened GitHub / form URL.
        case openedWeb
        /// Opened default mail client.
        case openedMail
        /// No destination configured — diagnostics copied for manual send.
        case copiedOnly
    }

    /// Always copies diagnostics, then opens Issues / mail when configured.
    @discardableResult
    static func openBugReport() -> BugReportOutcome {
        _ = copyDiagnosticsToPasteboard()

        if let web = bugReportWebURL() {
            NSWorkspace.shared.open(web)
            return .openedWeb
        }

        if let mail = bugReportMailtoURL() {
            NSWorkspace.shared.open(mail)
            return .openedMail
        }

        return .copiedOnly
    }

    /// Prefer explicit URL; enhance GitHub `issues/new` with title + body when possible.
    private static func bugReportWebURL() -> URL? {
        let raw = bugReportURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, var components = URLComponents(string: raw) else { return nil }

        let path = components.path.lowercased()
        let isGitHubNewIssue =
            (components.host?.contains("github.com") == true)
            && path.contains("/issues/new")

        if isGitHubNewIssue {
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "title" }) {
                items.append(URLQueryItem(name: "title", value: bugReportSubject))
            }
            if !items.contains(where: { $0.name == "body" }) {
                items.append(URLQueryItem(name: "body", value: bugReportTemplateBody))
            }
            components.queryItems = items
        }

        return components.url ?? URL(string: raw)
    }

    private static func bugReportMailtoURL() -> URL? {
        let email = supportEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: bugReportSubject),
            URLQueryItem(name: "body", value: bugReportTemplateBody)
        ]
        return components.url
    }

    /// Best available app icon for the About header (icns → named → file).
    @MainActor
    static var appIconImage: NSImage? {
        if let icon = NSApp.applicationIconImage, icon.size.width > 1 {
            return icon
        }
        if let named = NSImage(named: NSImage.Name("AppIcon")) {
            return named
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        if let resourceURL = Bundle.main.resourceURL {
            let png = resourceURL.appendingPathComponent("AppIcon.png")
            if let image = NSImage(contentsOf: png) {
                return image
            }
        }
        return nil
    }

    /// Opens a support channel in the default browser.
    @discardableResult
    static func open(_ channel: SupportChannel) -> Bool {
        guard let url = channel.url else { return false }
        return NSWorkspace.shared.open(url)
    }
}

// MARK: - SupportChannel

/// One external support option (Stats-style: icon + label → browser).
enum SupportChannel: String, CaseIterable, Identifiable {
    case paypal
    case koFi
    case githubSponsors
    case patreon
    case website

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paypal: return "PayPal"
        case .koFi: return "Ko-fi"
        case .githubSponsors: return "GitHub"
        case .patreon: return "Patreon"
        case .website: return L10n.t("channel.website")
        }
    }

    /// SF Symbol used until custom brand assets exist.
    var systemImage: String {
        switch self {
        case .paypal: return "creditcard.fill"
        case .koFi: return "cup.and.saucer.fill"
        case .githubSponsors: return "chevron.left.forwardslash.chevron.right"
        case .patreon: return "heart.circle.fill"
        case .website: return "globe"
        }
    }

    var help: String {
        switch self {
        case .paypal: return L10n.t("channel.paypal.help")
        case .koFi: return L10n.t("channel.kofi.help")
        case .githubSponsors: return L10n.t("channel.github.help")
        case .patreon: return L10n.t("channel.patreon.help")
        case .website: return L10n.t("channel.website.help")
        }
    }

    /// `nil` when the URL string in `AppInfo` is empty / invalid.
    var url: URL? {
        let raw: String
        switch self {
        case .paypal: raw = AppInfo.paypalURL
        case .koFi: raw = AppInfo.koFiURL
        case .githubSponsors: raw = AppInfo.githubSponsorsURL
        case .patreon: raw = AppInfo.patreonURL
        case .website: raw = AppInfo.websiteURL
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
