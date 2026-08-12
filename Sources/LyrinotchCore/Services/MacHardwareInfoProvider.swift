import Foundation

public actor MacHardwareInfoProvider {
    public typealias Loader = @Sendable () async throws -> ProcessResult

    public static let shared = MacHardwareInfoProvider(loader: {
        try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/system_profiler"),
            arguments: ["SPHardwareDataType", "-json", "-detailLevel", "mini"],
            timeout: 2
        )
    })

    private let loader: Loader
    private var cachedTask: Task<String?, Never>?

    public init(loader: @escaping Loader) {
        self.loader = loader
    }

    public func modelName() async -> String? {
        if let cachedTask {
            return await cachedTask.value
        }

        let loader = self.loader
        let task = Task<String?, Never> {
            do {
                return Self.parseModelName(from: try await loader())
            } catch {
                return nil
            }
        }
        cachedTask = task
        return await task.value
    }

    private nonisolated static func parseModelName(from result: ProcessResult) -> String? {
        guard result.exitCode == 0,
              let data = result.stdout.data(using: .utf8),
              let report = try? JSONDecoder().decode(SystemProfilerReport.self, from: data),
              let rawName = report.hardware.first?.modelName
        else { return nil }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

private struct SystemProfilerReport: Decodable {
    let hardware: [SystemProfilerHardware]

    private enum CodingKeys: String, CodingKey {
        case hardware = "SPHardwareDataType"
    }
}

private struct SystemProfilerHardware: Decodable {
    let modelName: String?

    private enum CodingKeys: String, CodingKey {
        case modelName = "machine_name"
    }
}
