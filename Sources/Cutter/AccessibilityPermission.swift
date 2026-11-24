import AppKit
import ApplicationServices

/// Tracks whether Cutter may control other apps' windows.
///
/// macOS sends no reliable callback when the user flips the switch in System Settings, so
/// this polls while access is missing and listens for the system's change notification
/// afterwards. A grant takes effect in the running app; no relaunch is needed.
final class AccessibilityPermission: ObservableObject {
    @Published private(set) var isTrusted: Bool

    private let check: () -> Bool
    private var pollTimer: Timer?
    private var changeObserver: NSObjectProtocol?

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    /// `check` answers whether access is granted right now. Replaceable so the settings
    /// window can be rendered in either state.
    init(check: @escaping () -> Bool = AXIsProcessTrusted) {
        self.check = check
        isTrusted = check()

        changeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification can arrive before the new state is readable.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.refresh()
            }
        }
        updatePolling()
    }

    deinit {
        pollTimer?.invalidate()
        if let changeObserver {
            DistributedNotificationCenter.default().removeObserver(changeObserver)
        }
    }

    func refresh() {
        let trusted = check()
        if trusted != isTrusted {
            isTrusted = trusted
            updatePolling()
        }
    }

    /// Adds Cutter to the Accessibility list, which makes macOS show its own prompt the
    /// first time, and opens that list in System Settings.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(Self.settingsURL)
    }

    private func updatePolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard !isTrusted else {
            return
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}
