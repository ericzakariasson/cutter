import AppKit
import CutterCore

/// Captures the next key press in Cutter's own window as a shortcut for one action.
///
/// Only one action records at a time. While this is recording, `AppModel` unregisters the
/// global shortcuts: otherwise pressing an existing one would trigger it instead of
/// reaching the recorder.
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var recordingAction: WindowAction?
    /// Feedback for the recording field, such as the modifiers held so far.
    @Published private(set) var hint: String?

    /// Called when a key press cannot be a global shortcut.
    var onRejectedKey: () -> Void = { NSSound.beep() }

    private var onCommit: ((KeyCombo?) -> Void)?
    private var eventMonitor: Any?
    private var focusObservers: [NSObjectProtocol] = []

    /// Starts recording for an action, or cancels if that action is already recording.
    /// `onCommit` receives the new shortcut, or nil when the user pressed Delete to clear it.
    func toggle(for action: WindowAction, onCommit: @escaping (KeyCombo?) -> Void) {
        let wasRecordingThisAction = recordingAction == action
        cancel()
        if !wasRecordingThisAction {
            start(for: action, onCommit: onCommit)
        }
    }

    func cancel() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        focusObservers.forEach(NotificationCenter.default.removeObserver)
        focusObservers = []
        onCommit = nil
        hint = nil
        if recordingAction != nil {
            recordingAction = nil
        }
    }

    private func start(for action: WindowAction, onCommit: @escaping (KeyCombo?) -> Void) {
        self.onCommit = onCommit
        recordingAction = action

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else {
                return event
            }
            return self.handle(event)
        }

        for name in [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.cancel()
            }
            focusObservers.append(observer)
        }
    }

    /// Returns nil to swallow the event so it does not also act on the window.
    func handle(_ event: NSEvent) -> NSEvent? {
        let modifiers = KeyCombo.Modifiers(event.modifierFlags)

        guard event.type == .keyDown else {
            hint = modifiers.isEmpty ? nil : modifiers.symbols
            return event
        }

        if modifiers.isEmpty, event.keyCode == KeyCode.escape {
            cancel()
            return nil
        }
        if modifiers.isEmpty, event.keyCode == KeyCode.delete || event.keyCode == KeyCode.forwardDelete {
            commit(nil)
            return nil
        }

        let combo = KeyCombo(keyCode: event.keyCode, modifiers: modifiers)
        guard combo.isValidGlobalShortcut else {
            hint = "Add ⌘, ⌃ or ⌥"
            onRejectedKey()
            return nil
        }
        commit(combo)
        return nil
    }

    private func commit(_ combo: KeyCombo?) {
        let onCommit = self.onCommit
        cancel()
        onCommit?(combo)
    }
}
