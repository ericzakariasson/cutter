import Carbon.HIToolbox
import CutterCore

/// Registers system-wide shortcuts with Carbon's `RegisterEventHotKey`.
///
/// This is the one hot key API that needs no permission and keeps the key press away from
/// the frontmost app. It is old but still what Rectangle and similar apps use.
final class HotKeyCenter {
    var onHotKey: ((WindowAction) -> Void)?

    private struct Registration {
        let reference: EventHotKeyRef
        let action: WindowAction
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextIdentifier: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    /// "CUTR"
    private static let signature: OSType = 0x4355_5452

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    var registeredCount: Int {
        registrations.count
    }

    /// Replaces every registration. Returns the status macOS gave for each shortcut it
    /// refused, for example because another app already registered the same one.
    @discardableResult
    func register(_ assignments: [(action: WindowAction, combo: KeyCombo)]) -> [WindowAction: OSStatus] {
        unregisterAll()
        installEventHandlerIfNeeded()

        var failures: [WindowAction: OSStatus] = [:]
        for (action, combo) in assignments {
            let identifier = nextIdentifier
            nextIdentifier += 1

            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(combo.keyCode),
                combo.modifiers.carbonFlags,
                EventHotKeyID(signature: Self.signature, id: identifier),
                GetEventDispatcherTarget(),
                0,
                &reference
            )
            if status == noErr, let reference {
                registrations[identifier] = Registration(reference: reference, action: action)
            } else {
                failures[action] = status
            }
        }
        return failures
    }

    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        registrations.removeAll()
    }

    fileprivate func handleHotKey(identifier: EventHotKeyID) {
        guard identifier.signature == Self.signature,
              let registration = registrations[identifier.id]
        else {
            return
        }
        onHotKey?(registration.action)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
}

private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else {
        return status
    }
    Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue().handleHotKey(identifier: identifier)
    return noErr
}
