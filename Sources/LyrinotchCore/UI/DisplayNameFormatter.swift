import Foundation

/// Produces stable, localized display names without relying on hardware strings
/// to localize Apple's built-in panel name.
public enum DisplayNameFormatter {
    public static func baseName(
        rawName: String,
        displayID: UInt32,
        isBuiltIn: Bool,
        localizedBuiltInName: String,
        modelName: String?
    ) -> String {
        if isBuiltIn {
            let trimmedModel = modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmedModel.isEmpty
                ? localizedBuiltInName
                : "\(localizedBuiltInName) · \(trimmedModel)"
        }

        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Display \(displayID)" : trimmed
    }

    public static func baseName(
        rawName: String,
        displayID: UInt32,
        isBuiltIn: Bool,
        localizedBuiltInName: String
    ) -> String {
        baseName(
            rawName: rawName,
            displayID: displayID,
            isBuiltIn: isBuiltIn,
            localizedBuiltInName: localizedBuiltInName,
            modelName: nil
        )
    }

    public static func pickerLabel(
        baseName: String,
        isMain: Bool,
        localizedMainRole: String
    ) -> String {
        isMain ? "\(baseName) · \(localizedMainRole)" : baseName
    }

}
