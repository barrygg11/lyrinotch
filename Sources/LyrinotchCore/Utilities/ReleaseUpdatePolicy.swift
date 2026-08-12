import Foundation

/// Pure update-policy helpers kept in Core so the security boundary is directly testable.
public enum ReleaseUpdatePolicy {
    public static func normalizeVersion(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value = String(value.dropFirst())
        }
        if let range = value.range(of: #"^[0-9]+(\.[0-9]+)*"#, options: .regularExpression) {
            return String(value[range])
        }
        return value
    }

    public static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? -1 : 1 }
        }
        return 0
    }

    public static func normalizedSHA256(_ digest: String?) -> String? {
        guard let digest else { return nil }
        let value = digest.lowercased().hasPrefix("sha256:")
            ? String(digest.dropFirst("sha256:".count))
            : digest
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex
    }

    public static func isTrustedGitHubReleaseAssetURL(
        _ url: URL,
        repositoryPath: String
    ) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com"
        else { return false }
        return url.path.hasPrefix("/\(repositoryPath)/releases/download/")
    }
}
