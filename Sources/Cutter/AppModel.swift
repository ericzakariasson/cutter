import AppKit
import Combine
import CutterCore

/// The app's state: the shortcut configuration and whether its shortcuts are live.
final class AppModel: ObservableObject {
    @Published private(set) var configuration: ShortcutConfiguration
    /// Actions whose shortcut macOS refused to register.
    @Published private(set) var failedRegistrations: Set<WindowAction> = []
    /// A one-line note about the last change, shown under the shortcut list.
    @Published private(set) var notice: String?

    let permission: AccessibilityPermission
    let recorder = ShortcutRecorder()
    let loginItem = LoginItem()

    /// Set by the app delegate; called when a shortcut needs the user's attention.
    var showSettings: (() -> Void)?

    private let store: ShortcutStore
    private let registersHotKeys: Bool
    private let hotKeys = HotKeyCenter()
    private let windows = WindowManager()
    private var cancellables: Set<AnyCancellable> = []

    /// Pass `registersHotKeys: false` to show the settings without taking over any keys.
    init(
        store: ShortcutStore = ShortcutStore(),
        permission: AccessibilityPermission = AccessibilityPermission(),
        registersHotKeys: Bool = true
    ) {
        self.store = store
        self.permission = permission
        self.registersHotKeys = registersHotKeys
        self.configuration = store.load()

        hotKeys.onHotKey = { [weak self] action in
            self?.perform(action)
        }

        // Shortcuts are live only while Cutter can act on them. Without Accessibility
        // access a registered shortcut would swallow the key press and do nothing.
        permission.$isTrusted
            .combineLatest(recorder.$recordingAction)
            .sink { [weak self] isTrusted, recordingAction in
                self?.syncHotKeys(isTrusted: isTrusted, isRecording: recordingAction != nil)
            }
            .store(in: &cancellables)
    }

    var registeredShortcutCount: Int {
        hotKeys.registeredCount
    }

    func perform(_ action: WindowAction) {
        do {
            try windows.perform(action)
        } catch WindowManagerError.accessibilityNotGranted {
            permission.refresh()
            showSettings?()
        } catch {
            NSLog("Cutter: %@ did nothing: %@", action.title, String(describing: error))
            NSSound.beep()
        }
    }

    func setShortcut(_ combo: KeyCombo?, for action: WindowAction) {
        let displaced = configuration.setShortcut(combo, for: action)
        if let combo, let displaced {
            notice = "\(KeyComboFormatter.string(for: combo)) now triggers \(action.title) instead of \(displaced.title)."
        } else {
            notice = nil
        }
        configurationDidChange()
    }

    func resetToDefaults() {
        configuration.resetToDefaults()
        notice = nil
        configurationDidChange()
    }

    private func configurationDidChange() {
        store.save(configuration)
        syncHotKeys(isTrusted: permission.isTrusted, isRecording: recorder.recordingAction != nil)
    }

    private func syncHotKeys(isTrusted: Bool, isRecording: Bool) {
        guard registersHotKeys else {
            return
        }
        guard isTrusted, !isRecording else {
            hotKeys.unregisterAll()
            if !isTrusted {
                failedRegistrations = []
            }
            log(isTrusted ? "shortcuts off while recording a shortcut" : "shortcuts off: Accessibility access not granted")
            return
        }

        let assignments = configuration.assignments
        let failures = hotKeys.register(assignments)
        failedRegistrations = Set(failures.keys)

        let registered = assignments
            .filter { failures[$0.action] == nil }
            .map { "\($0.action.title) \(KeyComboFormatter.string(for: $0.combo))" }
        var summary = "registered \(registered.count) shortcuts: \(registered.joined(separator: ", "))"
        for (action, status) in failures.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            summary += "; macOS refused the shortcut for \(action.title) (status \(status))"
        }
        log(summary)
    }

    private var lastLogLine: String?

    /// Logs shortcut state changes, without repeating a line when nothing changed.
    private func log(_ line: String) {
        guard line != lastLogLine else {
            return
        }
        lastLogLine = line
        NSLog("Cutter: %@", line)
    }
}
