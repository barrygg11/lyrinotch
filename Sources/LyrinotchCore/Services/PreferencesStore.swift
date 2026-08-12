import Foundation

/// Loads / saves `AppPreferences` via `UserDefaults`.
public struct PreferencesStore {
    /// Bump when default visual/behavior prefs change intentionally.
    public static let defaultSuiteKey = "app.lyrinotch.preferences.v8"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = PreferencesStore.defaultSuiteKey) {
        self.defaults = defaults
        self.key = key
    }

    /// In-memory store for unit tests (does not touch shared defaults).
    public static func ephemeral() -> PreferencesStore {
        let suiteName = "lyrinotch.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return PreferencesStore(defaults: defaults, key: "prefs")
    }

    public func load() -> AppPreferences {
        guard let data = defaults.data(forKey: key) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(AppPreferences.self, from: data)
        } catch {
            return .default
        }
    }

    public func save(_ preferences: AppPreferences) {
        do {
            let data = try JSONEncoder().encode(preferences)
            defaults.set(data, forKey: key)
        } catch {
            // Best-effort persistence; ignore encode failures.
        }
    }
}
