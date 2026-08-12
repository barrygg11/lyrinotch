import Foundation

/// UI language for Lyrinotch (Settings → 系統).
public enum AppLanguage: String, Codable, Sendable, CaseIterable, Equatable, Identifiable {
    /// Follow macOS preferred languages (resolved at apply time).
    case system = "system"
    case traditionalChinese = "zh-Hant"
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"

    public var id: String { rawValue }

    /// Concrete language used for string tables (never `.system`).
    public var resolved: AppLanguage {
        switch self {
        case .system: return Self.detectSystemLanguage()
        case .traditionalChinese, .simplifiedChinese, .english, .japanese:
            return self
        }
    }

    /// BCP-47 / Foundation locale id for the **resolved** language.
    public var localeIdentifier: String {
        resolved.rawValue == "system" ? "zh-Hant" : resolved.rawValue
    }

    public var locale: Locale { Locale(identifier: localeIdentifier) }

    /// Always shown in a readable form in the picker.
    public var nativeDisplayName: String {
        switch self {
        case .system:
            // Dual-script so it stays clear in every UI language.
            let current = Self.detectSystemLanguage().nativeDisplayName
            return "跟隨系統 / System（\(current)）"
        case .traditionalChinese: return "繁體中文"
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        case .japanese: return "日本語"
        }
    }

    /// Best match from the user’s preferred languages (never returns `.system`).
    public static func detectSystemLanguage() -> AppLanguage {
        detectSystemLanguage(preferredLanguages: Locale.preferredLanguages)
    }

    static func detectSystemLanguage(preferredLanguages: [String]) -> AppLanguage {
        for code in preferredLanguages {
            let lower = code.lowercased()
            if lower.hasPrefix("zh-hant") || lower.hasPrefix("zh-tw") || lower.hasPrefix("zh-hk")
                || lower.hasPrefix("zh-mo") {
                return .traditionalChinese
            }
            if lower.hasPrefix("zh-hans") || lower.hasPrefix("zh-cn") || lower.hasPrefix("zh-sg")
                || lower == "zh" {
                return .simplifiedChinese
            }
            if lower.hasPrefix("ja") { return .japanese }
            if lower.hasPrefix("en") { return .english }
        }
        // English is the least surprising fallback for languages for which the
        // app has no translation. Falling back to Chinese made first launch
        // unreadable for users of Korean, French, German, and other locales.
        return .english
    }

    /// - Note: Prefer `detectSystemLanguage()`; kept for older call sites.
    public static func matchedToSystem() -> AppLanguage {
        detectSystemLanguage()
    }
}
