import XCTest
@testable import Lyrinotch
@testable import LyrinotchCore

final class AutomationPermissionsStateTests: XCTestCase {
    @MainActor
    func testPassiveUnknownCannotOverwriteExplicitAuthorization() async {
        let state = AutomationPermissionsState(
            passiveProbe: { _ in .unknown },
            explicitProbe: { _ in .authorized }
        )

        await state.verify(.appleMusic)
        await state.refreshPassive()

        XCTAssertEqual(state.status(for: .appleMusic), .authorized)
    }

    @MainActor
    func testLatePassiveResultCannotOverwriteNewerExplicitResult() async {
        let passiveGate = AutomationPermissionProbeGate()
        let state = AutomationPermissionsState(
            passiveProbe: { target in
                await passiveGate.result(for: target)
            },
            explicitProbe: { _ in .playerNotRunning }
        )

        let refreshTask = Task { await state.refreshPassive() }
        await passiveGate.waitUntilStarted(.appleMusic)
        await passiveGate.waitUntilStarted(.spotify)

        await state.verify(.appleMusic)
        await passiveGate.complete(.appleMusic, with: .unknown)
        await passiveGate.complete(.spotify, with: .unknown)
        await refreshTask.value

        XCTAssertEqual(state.status(for: .appleMusic), .playerNotRunning)
    }

    @MainActor
    func testVerifyAllUsesExplicitProbeForEveryPlayer() async {
        let recorder = AutomationPermissionProbeRecorder()
        let state = AutomationPermissionsState(
            passiveProbe: { _ in .unknown },
            explicitProbe: { target in
                await recorder.record(target)
                return target == .appleMusic ? .authorized : .denied
            }
        )

        await state.verifyAll()

        let targets = await recorder.recordedTargets()
        XCTAssertEqual(targets, [.appleMusic, .spotify])
        XCTAssertEqual(state.status(for: .appleMusic), .authorized)
        XCTAssertEqual(state.status(for: .spotify), .denied)
    }

    @MainActor
    func testVerifyAllWaitsForFirstPlayerBeforeStartingSecond() async {
        let gate = AutomationPermissionProbeGate()
        let state = AutomationPermissionsState(
            passiveProbe: { _ in .unknown },
            explicitProbe: { target in
                await gate.result(for: target)
            }
        )

        let task = Task { await state.verifyAll() }
        await gate.waitUntilStarted(.appleMusic)
        for _ in 0..<20 { await Task.yield() }

        let spotifyStartedEarly = await gate.hasStarted(.spotify)
        XCTAssertFalse(spotifyStartedEarly)

        await gate.complete(.appleMusic, with: .authorized)
        await gate.waitUntilStarted(.spotify)
        await gate.complete(.spotify, with: .authorized)
        await task.value
    }

    @MainActor
    func testPassiveRefreshNeverInvokesExplicitProbe() async {
        let recorder = AutomationPermissionProbeRecorder()
        let state = AutomationPermissionsState(
            passiveProbe: { _ in .unknown },
            explicitProbe: { target in
                await recorder.record(target)
                return .authorized
            }
        )

        await state.refreshPassive()

        let targets = await recorder.recordedTargets()
        XCTAssertTrue(targets.isEmpty)
    }

    @MainActor
    func testVerifyPublishesCheckingStateUntilProbeCompletes() async {
        let gate = AutomationPermissionProbeGate()
        let state = AutomationPermissionsState(
            passiveProbe: { _ in .unknown },
            explicitProbe: { target in
                await gate.result(for: target)
            }
        )

        let task = Task { await state.verify(.spotify) }
        await gate.waitUntilStarted(.spotify)

        XCTAssertTrue(state.isChecking(.spotify))

        await gate.complete(.spotify, with: .timedOut)
        await task.value

        XCTAssertFalse(state.isChecking(.spotify))
        XCTAssertEqual(state.status(for: .spotify), .timedOut)
    }

    @MainActor
    func testSecondInteractiveRequestDoesNotOverlapActiveCheck() async {
        let gate = AutomationPermissionProbeGate()
        let state = AutomationPermissionsState(
            passiveProbe: { _ in .unknown },
            explicitProbe: { target in
                await gate.result(for: target)
            }
        )

        let musicTask = Task { await state.verify(.appleMusic) }
        await gate.waitUntilStarted(.appleMusic)

        let spotifyTask = Task { await state.verify(.spotify) }
        for _ in 0..<20 { await Task.yield() }
        let spotifyStarted = await gate.hasStarted(.spotify)

        await gate.complete(.appleMusic, with: .authorized)
        if spotifyStarted {
            await gate.complete(.spotify, with: .authorized)
        }
        await musicTask.value
        await spotifyTask.value

        XCTAssertFalse(spotifyStarted)
    }
}

private actor AutomationPermissionProbeRecorder {
    private var targets: [TargetPlayerApp] = []

    func record(_ target: TargetPlayerApp) {
        targets.append(target)
    }

    func recordedTargets() -> [TargetPlayerApp] {
        targets
    }
}

private actor AutomationPermissionProbeGate {
    private var started = Set<TargetPlayerApp>()
    private var continuations: [
        TargetPlayerApp: CheckedContinuation<AutomationPermissionStatus, Never>
    ] = [:]

    func result(for target: TargetPlayerApp) async -> AutomationPermissionStatus {
        started.insert(target)
        return await withCheckedContinuation { continuation in
            continuations[target] = continuation
        }
    }

    func waitUntilStarted(_ target: TargetPlayerApp) async {
        while !started.contains(target) {
            await Task.yield()
        }
    }

    func hasStarted(_ target: TargetPlayerApp) -> Bool {
        started.contains(target)
    }

    func complete(
        _ target: TargetPlayerApp,
        with status: AutomationPermissionStatus
    ) {
        continuations.removeValue(forKey: target)?.resume(returning: status)
    }
}
