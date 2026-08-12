import Foundation
import XCTest
@testable import LyrinotchCore

final class DisplayNameFormatterTests: XCTestCase {
    func testBuiltInDisplayIncludesTrimmedMacModelName() {
        let name = DisplayNameFormatter.baseName(
            rawName: "Built-in Retina Display",
            displayID: 1,
            isBuiltIn: true,
            localizedBuiltInName: "內建顯示器",
            modelName: "  MacBook Pro  "
        )

        XCTAssertEqual(name, "內建顯示器 · MacBook Pro")
    }

    func testBuiltInDisplayFallsBackWhenModelNameIsMissing() {
        let name = DisplayNameFormatter.baseName(
            rawName: "Built-in Retina Display",
            displayID: 1,
            isBuiltIn: true,
            localizedBuiltInName: "內建顯示器",
            modelName: nil
        )

        XCTAssertEqual(name, "內建顯示器")
    }

    func testExternalDisplayIgnoresMacModelName() {
        let name = DisplayNameFormatter.baseName(
            rawName: "  Mi Monitor  ",
            displayID: 2,
            isBuiltIn: false,
            localizedBuiltInName: "內建顯示器",
            modelName: "MacBook Pro"
        )

        XCTAssertEqual(name, "Mi Monitor")
    }

    func testMainDisplayRoleIsAppendedAfterModelName() {
        let label = DisplayNameFormatter.pickerLabel(
            baseName: "內建顯示器 · MacBook Pro",
            isMain: true,
            localizedMainRole: "主要顯示器"
        )

        XCTAssertEqual(label, "內建顯示器 · MacBook Pro · 主要顯示器")
        XCTAssertFalse(label.contains("瀏海"))
    }

    func testEveryLanguageUsesMacOSDisplayTerminology() {
        XCTAssertEqual(L10n.zhHant["screen.builtin"], "內建顯示器")
        XCTAssertEqual(L10n.zhHant["screen.hint_main"], "主要顯示器")
        XCTAssertEqual(L10n.zhHans["screen.builtin"], "内建显示器")
        XCTAssertEqual(L10n.zhHans["screen.hint_main"], "主显示器")
        XCTAssertEqual(L10n.en["screen.builtin"], "Built-in Display")
        XCTAssertEqual(L10n.en["screen.hint_main"], "Main Display")
        XCTAssertEqual(L10n.ja["screen.builtin"], "内蔵ディスプレイ")
        XCTAssertEqual(L10n.ja["screen.hint_main"], "メインディスプレイ")
    }

    func testObsoleteNotchPickerOverloadIsNotPublicAPI() throws {
        let modulesDirectory = try lyrinotchCoreModulesDirectory()
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DisplayNameFormatterAPI-\(UUID().uuidString).swift")
        let source = """
        import LyrinotchCore

        _ = DisplayNameFormatter.pickerLabel(
            baseName: "Built-in Display",
            isMain: true,
            hasNotch: true,
            localizedMainRole: "Main Display",
            localizedNotchHint: "Notch"
        )
        """
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let process = Process()
        let diagnostics = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "swiftc",
            "-typecheck",
            "-I", modulesDirectory.path,
            sourceURL.path
        ]
        process.standardError = diagnostics
        try process.run()
        process.waitUntilExit()
        let output = String(
            data: diagnostics.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        XCTAssertNotEqual(process.terminationStatus, 0, "Obsolete overload still compiles")
        XCTAssertTrue(
            output.contains("extra arguments") || output.contains("incorrect argument labels"),
            "Unexpected compiler diagnostic: \(output)"
        )
    }

    private func lyrinotchCoreModulesDirectory() throws -> URL {
        var directory = Bundle(for: Self.self).bundleURL

        while directory.path != "/" {
            let candidates = [
                directory.appendingPathComponent("Modules", isDirectory: true),
                directory
            ]

            if let match = candidates.first(where: { candidate in
                FileManager.default.fileExists(
                    atPath: candidate.appendingPathComponent("LyrinotchCore.swiftmodule").path
                )
            }) {
                return match
            }

            directory.deleteLastPathComponent()
        }

        throw XCTSkip("Unable to locate LyrinotchCore.swiftmodule from the test bundle")
    }
}
