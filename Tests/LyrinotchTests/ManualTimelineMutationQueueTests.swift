import XCTest
@testable import Lyrinotch

final class ManualTimelineMutationQueueTests: XCTestCase {
    @MainActor
    func testEnqueuedMutationsRunInUserActionOrder() async {
        let queue = ManualTimelineMutationQueue()
        let gate = ManualMutationQueueGate()
        let recorder = ManualMutationRecorder()

        let first = queue.enqueue {
            await gate.suspend()
            await recorder.append(1)
        }
        let second = queue.enqueue {
            await recorder.append(2)
        }

        await gate.waitUntilSuspended()
        for _ in 0..<20 { await Task.yield() }
        let whileBlocked = await recorder.values()
        XCTAssertEqual(whileBlocked, [])

        await gate.resume()
        await first.value
        await second.value

        let completed = await recorder.values()
        XCTAssertEqual(completed, [1, 2])
    }
}

private actor ManualMutationQueueGate {
    private var isSuspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        isSuspended = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSuspended() async {
        while !isSuspended {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ManualMutationRecorder {
    private var recorded: [Int] = []

    func append(_ value: Int) {
        recorded.append(value)
    }

    func values() -> [Int] {
        recorded
    }
}
