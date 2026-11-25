import AppKit
import ApplicationServices
import CutterCore
import ServiceManagement

/// Checks that run instead of the menu bar app:
///
///     Cutter.app/Contents/MacOS/Cutter --diagnose
///     open -n Cutter.app --stdout /tmp/cutter-self-test.log --args --self-test
enum CommandLineTool {
    /// Returns an exit code when the arguments asked for a terminal task, or nil to start
    /// the app as usual.
    static func run(_ arguments: [String]) -> Int32? {
        switch arguments.first {
        case "--diagnose":
            diagnose()
            return 0
        case "--self-test":
            return SelfTest.run()
        case "--self-test-window":
            return SelfTest.runWindowHost(screenIndex: arguments.dropFirst().first)
        case "--help", "-h":
            print("usage: Cutter [--diagnose | --self-test]")
            return 0
        #if DEBUG
        case "--snapshot-settings":
            return snapshotSettings(to: arguments.dropFirst().first)
        case "--snapshot-screenshots":
            return ScreenshotPanelSnapshot.run(to: arguments.dropFirst().first)
        #endif
        default:
            return nil
        }
    }

    /// Prints what Cutter sees. It only reads: it changes no setting and registers no
    /// shortcut, so it is safe to run while Cutter is in use.
    private static func diagnose() {
        print("Cutter \(AppInfo.version) (\(Bundle.main.bundleIdentifier ?? "no bundle identifier"))")
        print("Location: \(Bundle.main.bundlePath)")
        print("Accessibility access: \(AXIsProcessTrusted() ? "allowed" : "not allowed")")
        print("Launch at login: \(LoginItem.describe(SMAppService.mainApp.status))")

        let layout = ScreenLayout(cocoaScreens: NSScreen.screens.map { ($0.frame, $0.visibleFrame) })
        print("Screens (top-left origin):")
        for (index, screen) in layout.screens.enumerated() {
            print("  \(index + 1). \(describe(screen.frame)), usable \(describe(screen.visibleFrame))")
        }
        let order = layout.displayOrder.map { String($0 + 1) }.joined(separator: ", ")
        print("Order for moving between displays: \(order)")

        let configuration = ShortcutStore().load()
        print("Shortcuts:")
        for action in WindowAction.allCases {
            let title = action.title.padding(toLength: 26, withPad: " ", startingAt: 0)
            let shortcut = configuration.shortcut(for: action).map(KeyComboFormatter.string(for:)) ?? "-"
            print("  \(title)\(shortcut)")
        }
    }

    private static func describe(_ rect: CGRect) -> String {
        "\(Int(rect.width))x\(Int(rect.height)) at (\(Int(rect.minX)), \(Int(rect.minY)))"
    }

    #if DEBUG
    /// Renders the settings window to PNGs without showing it, before and after
    /// Accessibility access, for checking the layout from a terminal. It uses throwaway
    /// settings and registers no shortcuts. Debug builds only.
    private static func snapshotSettings(to directory: String?) -> Int32 {
        guard let directory else {
            print("usage: Cutter --snapshot-settings <directory>")
            return 2
        }
        _ = NSApplication.shared

        var isTrusted = false
        let permission = AccessibilityPermission { isTrusted }
        let model = AppModel(
            store: ShortcutStore(storage: InMemoryShortcutStorage()),
            permission: permission,
            hotKeys: NoHotKeys()
        )
        let window = SettingsWindowController(model: model).window

        do {
            try snapshot(window, to: "\(directory)/settings-needs-access.png")
            isTrusted = true
            permission.refresh()

            // The recorder asking before it accepts ⌘Q.
            model.recorder.onRejectedKey = {}
            model.recorder.characterForKeyCode = { _ in "q" }
            model.recorder.toggle(for: .maximize) { _ in }
            if let commandQ = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0,
                context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12
            ) {
                _ = model.recorder.handle(commandQ)
            }
            try snapshot(window, to: "\(directory)/settings-well-known-shortcut.png")
            model.recorder.cancel()

            model.setShortcut(KeyCombo(keyCode: KeyCode.returnKey, modifiers: [.control, .option]), for: .toggleFullScreen)
            try snapshot(window, to: "\(directory)/settings-access-allowed.png")
        } catch {
            print("Failed: \(error.localizedDescription)")
            return 1
        }
        return 0
    }

    /// Takes over no keys.
    private final class NoHotKeys: HotKeyRegistering {
        var onHotKey: ((WindowAction) -> Void)?

        func register(_ assignments: [(action: WindowAction, combo: KeyCombo)]) -> [WindowAction: OSStatus] {
            [:]
        }

        func unregisterAll() {}
    }

    private static func snapshot(_ window: NSWindow, to path: String) throws {
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path): content \(Int(view.bounds.width))x\(Int(view.bounds.height)), window top at \(Int(window.frame.maxY))")
    }
    #endif
}
