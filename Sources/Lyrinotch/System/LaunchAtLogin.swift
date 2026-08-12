import Foundation
import ServiceManagement

/// Wraps `SMAppService` for open-at-login (requires a real `.app` bundle).
enum LaunchAtLogin {
    enum Status: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case notAvailable(String)
    }

    static var status: Status {
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notAvailable("請執行打包後的 Lyrinotch.app（不要用 swift run）才能設定開機啟動。")
        case .notRegistered:
            return .disabled
        @unknown default:
            return .disabled
        }
    }

    static var isEnabled: Bool {
        if case .enabled = status { return true }
        return false
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Result<Status, Error> {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            return .success(status)
        } catch {
            return .failure(error)
        }
    }
}
