import Foundation

/// Lightweight in-app localization (no .xcstrings required for SPM agent).
/// Set `L10n.current` when the user changes language; UI should rebuild with `.id(L10n.current)`.
public enum L10n {
    /// Active UI language (mirrors `AppPreferences.preferredLanguage`).
    /// Written from the main app; read from UI / strings. Not crossed between actors heavily.
    nonisolated(unsafe) public static var current: AppLanguage = .traditionalChinese

    public static func t(_ key: String) -> String {
        let resolved = current.resolved
        if let value = table(for: resolved)[key] { return value }
        if let value = table(for: .traditionalChinese)[key] { return value }
        return key
    }

    public static func t(_ key: String, _ args: CVarArg...) -> String {
        let format = t(key)
        return String(format: format, locale: current.resolved.locale, arguments: args)
    }

    /// Apply preference (may be `.system`) → store resolved concrete language for tables.
    public static func apply(_ preference: AppLanguage) {
        current = preference.resolved
    }

    private static func table(for language: AppLanguage) -> [String: String] {
        switch language.resolved {
        case .system:
            return zhHant
        case .traditionalChinese: return zhHant
        case .simplifiedChinese: return zhHans
        case .english: return en
        case .japanese: return ja
        }
    }
}
