import Foundation

/// Shared bounds for data that originates outside the application.
public enum LyricsInputLimits {
    public static let maximumNetworkResponseBytes = 1_048_576
    public static let maximumNetworkRecords = 200
    public static let maximumNetworkSourceLines = 20_000
    public static let maximumNetworkTimedLines = 10_000
    public static let maximumNetworkCharactersPerLine = 16_384

    public static let maximumTrackDuration: TimeInterval = 86_400
    public static let maximumEmbeddedOffsetSeconds: TimeInterval = 300
    public static let maximumTimestampSeconds: TimeInterval = 86_400

    public static func validDuration(_ value: TimeInterval?) -> TimeInterval? {
        guard let value,
              value.isFinite,
              value >= 0,
              value <= maximumTrackDuration
        else { return nil }
        return value
    }

    public static func validTimestamp(_ value: TimeInterval) -> TimeInterval? {
        guard value.isFinite,
              value >= 0,
              value <= maximumTimestampSeconds
        else { return nil }
        return value
    }

    public static func textFitsNetworkLimits(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count <= maximumNetworkSourceLines else { return false }
        return lines.allSatisfy { $0.count <= maximumNetworkCharactersPerLine }
    }
}
