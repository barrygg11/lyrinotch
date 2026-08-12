import AppKit

/// Global + local mouse monitors (vibe-notch EventMonitor pattern).
@MainActor
final class MouseEventMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> Void

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handler(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handler(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}
