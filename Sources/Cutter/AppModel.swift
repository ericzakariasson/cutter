import AppKit
import Combine
import CutterCore

/// Registers system-wide shortcuts. `HotKeyCenter` is the real one.
protocol HotKeyRegistering: AnyObject {
    var onHotKey: ((WindowAction) -> Void)? { get set }

    /// Replaces every registration. Returns the status for each shortcut macOS rejected.
    func register(_ assignments: [(action: WindowAction, combo: KeyCombo)]) -> [WindowAction: OSStatus]
    func unregisterAll()
}

/// The app's state: the shortcut configuration and whether its shortcuts are live.
final class AppModel: ObservableObject {
    @Published private(set) var configuration: ShortcutConfiguration
    /// Actions whose shortcut macOS rejected, with the status it gave.
    @Published private(set) var failedRegistrations: [WindowAction: OSStatus] = [:]
    /// A one-line note about the last change, shown under the shortcut list.
    @Published private(set) var notice: String?

    let permission: AccessibilityPermission
    let recorder = ShortcutRecorder()
    let loginItem = LoginItem()

    /// Set by the app delegate; called when a shortcut needs the user's attention.
    var showSettings: (() -> Void)?

    private let store: ShortcutStore
    private let hotKeys: HotKeyRegistering
    private let act: (WindowAction) throws -> Void
    private let menuAnswersTo: (KeyCombo) -> Bool
    private var isMenuOpen = false
    private var cancellables: Set<AnyCancellable> = []

    /// - Parameters:
    ///   - act: what carries out an action. The default acts on the focused window; tests
    ///     pass their own so that they can never move anyone's windows.
    ///   - menuAnswersTo: whether the open menu runs a shortcut's item by itself.
    init(
        store: ShortcutStore = ShortcutStore(),
        permission: AccessibilityPermission = AccessibilityPermission(),
        hotKeys: HotKeyRegistering = HotKeyCenter(),
        act: ((WindowAction) throws -> Void)? = nil,
        menuAnswersTo: @escaping (KeyCombo) -> Bool = KeyComboFormatter.menuAnswers(to:)
    ) {
        self.store = store
        self.permission = permission
        self.hotKeys = hotKeys
        self.menuAnswersTo = menuAnswersTo
        self.configuration = store.load()
        if let act {
            self.act = act
        } else {
            let windows = WindowManager()
            self.act = { try windows.perform($0) }
        }

        hotKeys.onHotKey = { [weak self] action in
            self?.perform(action)
        }

        permission.$isTrusted
            .combineLatest(recorder.$recordingAction)
            .sink { [weak self] isTrusted, recordingAction in
                self?.syncHotKeys(isTrusted: isTrusted, isRecording: recordingAction != nil)
            }
            .store(in: &cancellables)
    }

    func perform(_ action: WindowAction) {
        do {
            try act(action)
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

    /// While Cutter's menu is open, its items answer to the same keys as the global
    /// shortcuts. The global ones step aside so that one key press runs an action once.
    /// A shortcut the menu does not answer to stays registered, so it keeps working.
    func menuDidOpen() {
        isMenuOpen = true
        syncHotKeys()
    }

    func menuDidClose() {
        isMenuOpen = false
        syncHotKeys()
    }

    private func configurationDidChange() {
        store.save(configuration)
        syncHotKeys()
    }

    private func syncHotKeys() {
        syncHotKeys(isTrusted: permission.isTrusted, isRecording: recorder.recordingAction != nil)
    }

    /// Shortcuts are live only while Cutter can act on them: without Accessibility access
    /// a registered shortcut would swallow the key press and do nothing. They also pause
    /// while a shortcut is being recorded, so the recorder sees the keys, and while the
    /// menu is open.
    private func syncHotKeys(isTrusted: Bool, isRecording: Bool) {
        guard isTrusted else {
            hotKeys.unregisterAll()
            failedRegistrations = [:]
            log("shortcuts off: Accessibility access not granted")
            return
        }
        guard !isRecording else {
            hotKeys.unregisterAll()
            return
        }
        let assignments = configuration.assignments
        guard !isMenuOpen else {
            _ = hotKeys.register(assignments.filter { !menuAnswersTo($0.combo) })
            return
        }

        let failures = hotKeys.register(assignments)
        failedRegistrations = failures

        let registered = assignments
            .filter { failures[$0.action] == nil }
            .map { "\($0.action.title) \(KeyComboFormatter.string(for: $0.combo))" }
        var summary = "registered \(registered.count) shortcuts: \(registered.joined(separator: ", "))"
        for (action, status) in failures.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            summary += "; macOS rejected the shortcut for \(action.title) (status \(status))"
        }
        log(summary)
    }

    private var lastLogLine: String?

    /// Logs shortcut state changes. Pausing and resuming with nothing changed logs nothing.
    private func log(_ line: String) {
        guard line != lastLogLine else {
            return
        }
        lastLogLine = line
        NSLog("Cutter: %@", line)
    }
}
