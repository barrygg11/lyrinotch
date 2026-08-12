import AppKit
import Carbon

/// Registers global hotkeys via Carbon:
/// - ⌘⇧L show/hide overlay
/// - ⌘⇧E expand/collapse
/// - ⌘⇧] lyric delay +0.5s
/// - ⌘⇧[ lyric delay −0.5s
@MainActor
final class GlobalHotKeyMonitor {
    static let shared = GlobalHotKeyMonitor()

    private var visibilityHotKeyRef: EventHotKeyRef?
    private var expandHotKeyRef: EventHotKeyRef?
    private var delayPlusHotKeyRef: EventHotKeyRef?
    private var delayMinusHotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private let signature = OSType(0x4C595249) // 'LYRI'
    private let visibilityID: UInt32 = 1
    private let expandID: UInt32 = 2
    private let delayPlusID: UInt32 = 3
    private let delayMinusID: UInt32 = 4

    /// ⌘⇧L — show / hide overlay.
    var onToggleVisibility: (() -> Void)?
    /// ⌘⇧E — collapse / expand island.
    var onToggleExpand: (() -> Void)?
    /// ⌘⇧] — lyric timeline +0.5s.
    var onLyricDelayPlus: (() -> Void)?
    /// ⌘⇧[ — lyric timeline −0.5s.
    var onLyricDelayMinus: (() -> Void)?

    private init() {}

    var isRegistered: Bool { visibilityHotKeyRef != nil }

    func start() {
        guard visibilityHotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let handler: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return noErr }

            var hkID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            guard err == noErr else { return noErr }
            guard hkID.signature == OSType(0x4C595249) else { return noErr }

            let monitorAddress = UInt(bitPattern: userData)
            let hotKeyID = hkID.id
            Task { @MainActor in
                guard let pointer = UnsafeRawPointer(bitPattern: monitorAddress) else { return }
                let monitor = Unmanaged<GlobalHotKeyMonitor>
                    .fromOpaque(pointer)
                    .takeUnretainedValue()
                switch hotKeyID {
                case 1: monitor.onToggleVisibility?()
                case 2: monitor.onToggleExpand?()
                case 3: monitor.onLyricDelayPlus?()
                case 4: monitor.onLyricDelayMinus?()
                default: break
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            userData,
            &handlerRef
        )

        let modifiers = UInt32(cmdKey | shiftKey)

        var visRef: EventHotKeyRef?
        let visStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_L),
            modifiers,
            EventHotKeyID(signature: signature, id: visibilityID),
            GetApplicationEventTarget(),
            0,
            &visRef
        )
        if visStatus == noErr {
            visibilityHotKeyRef = visRef
        }

        var expRef: EventHotKeyRef?
        let expStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_E),
            modifiers,
            EventHotKeyID(signature: signature, id: expandID),
            GetApplicationEventTarget(),
            0,
            &expRef
        )
        if expStatus == noErr {
            expandHotKeyRef = expRef
        }

        var plusRef: EventHotKeyRef?
        let plusStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_RightBracket),
            modifiers,
            EventHotKeyID(signature: signature, id: delayPlusID),
            GetApplicationEventTarget(),
            0,
            &plusRef
        )
        if plusStatus == noErr {
            delayPlusHotKeyRef = plusRef
        }

        var minusRef: EventHotKeyRef?
        let minusStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_LeftBracket),
            modifiers,
            EventHotKeyID(signature: signature, id: delayMinusID),
            GetApplicationEventTarget(),
            0,
            &minusRef
        )
        if minusStatus == noErr {
            delayMinusHotKeyRef = minusRef
        }
    }

    func stop() {
        if let visibilityHotKeyRef {
            UnregisterEventHotKey(visibilityHotKeyRef)
            self.visibilityHotKeyRef = nil
        }
        if let expandHotKeyRef {
            UnregisterEventHotKey(expandHotKeyRef)
            self.expandHotKeyRef = nil
        }
        if let delayPlusHotKeyRef {
            UnregisterEventHotKey(delayPlusHotKeyRef)
            self.delayPlusHotKeyRef = nil
        }
        if let delayMinusHotKeyRef {
            UnregisterEventHotKey(delayMinusHotKeyRef)
            self.delayMinusHotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

}
