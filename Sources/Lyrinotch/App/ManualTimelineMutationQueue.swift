import Foundation

/// Preserves user-action order for durable manual-lyrics mutations that cross
/// actor boundaries. Operations are intentionally not cancelled on track
/// navigation: an explicit save/removal still belongs to its captured track.
@MainActor
final class ManualTimelineMutationQueue {
    private var tail: Task<Void, Never>?

    @discardableResult
    func enqueue(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        let predecessor = tail
        let task = Task {
            await predecessor?.value
            await operation()
        }
        tail = task
        return task
    }

    func waitForIdle() async {
        await tail?.value
    }
}
