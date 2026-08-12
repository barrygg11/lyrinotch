import Foundation
import Observation
import LyrinotchCore

/// Owns permission-check presentation and prevents an inconclusive passive
/// refresh from replacing a result produced by an explicit user check.
@MainActor
@Observable
final class AutomationPermissionsState {
    typealias Probe = @Sendable (TargetPlayerApp) async -> AutomationPermissionStatus

    private(set) var appleMusicStatus: AutomationPermissionStatus = .unknown
    private(set) var spotifyStatus: AutomationPermissionStatus = .unknown
    private(set) var checkingTargets = Set<TargetPlayerApp>()

    @ObservationIgnored private let passiveProbe: Probe
    @ObservationIgnored private let explicitProbe: Probe
    @ObservationIgnored private var generations: [TargetPlayerApp: Int] = [:]

    init(
        passiveProbe: @escaping Probe = { target in
            await Task.detached(priority: .userInitiated) {
                AutomationPermissionHelper.status(for: target)
            }.value
        },
        explicitProbe: @escaping Probe = { target in
            await Task.detached(priority: .userInitiated) {
                AutomationPermissionHelper.requestPermission(for: target)
            }.value
        }
    ) {
        self.passiveProbe = passiveProbe
        self.explicitProbe = explicitProbe
    }

    func status(for target: TargetPlayerApp) -> AutomationPermissionStatus {
        switch target {
        case .appleMusic: appleMusicStatus
        case .spotify: spotifyStatus
        }
    }

    func isChecking(_ target: TargetPlayerApp) -> Bool {
        checkingTargets.contains(target)
    }

    var isCheckingAny: Bool {
        !checkingTargets.isEmpty
    }

    func refreshPassive() async {
        let musicGeneration = generation(for: .appleMusic)
        let spotifyGeneration = generation(for: .spotify)
        async let music = passiveProbe(.appleMusic)
        async let spotify = passiveProbe(.spotify)
        let (musicStatus, spotifyStatus) = await (music, spotify)
        applyPassive(
            musicStatus,
            for: .appleMusic,
            expectedGeneration: musicGeneration
        )
        applyPassive(
            spotifyStatus,
            for: .spotify,
            expectedGeneration: spotifyGeneration
        )
    }

    /// Checks players one at a time so macOS never presents two Automation
    /// consent sheets simultaneously.
    func verifyAll() async {
        for target in TargetPlayerApp.allCases {
            await verify(target)
        }
    }

    func verify(_ target: TargetPlayerApp) async {
        guard !isCheckingAny else { return }
        let generation = nextGeneration(for: target)
        checkingTargets.insert(target)
        let result = await explicitProbe(target)
        guard generations[target] == generation else { return }
        setStatus(result, for: target)
        checkingTargets.remove(target)
    }

    private func applyPassive(
        _ incoming: AutomationPermissionStatus,
        for target: TargetPlayerApp,
        expectedGeneration: Int
    ) {
        guard generation(for: target) == expectedGeneration else { return }
        switch status(for: target) {
        case .authorized, .denied, .notDetermined, .timedOut:
            return
        case .unknown, .playerNotRunning:
            setStatus(incoming, for: target)
        }
    }

    private func setStatus(
        _ status: AutomationPermissionStatus,
        for target: TargetPlayerApp
    ) {
        switch target {
        case .appleMusic: appleMusicStatus = status
        case .spotify: spotifyStatus = status
        }
    }

    private func nextGeneration(for target: TargetPlayerApp) -> Int {
        let next = generation(for: target) &+ 1
        generations[target] = next
        return next
    }

    private func generation(for target: TargetPlayerApp) -> Int {
        generations[target] ?? 0
    }
}
