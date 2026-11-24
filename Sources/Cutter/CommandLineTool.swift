import AppKit
import ApplicationServices
import CutterCore
import ServiceManagement

/// Checks that run instead of the menu bar app:
///
///     Cutter.app/Contents/MacOS/Cutter --diagnose
///     Cutter.app/Contents/MacOS/Cutter --login-item status|on|off
///     open -n Cutter.app --stdout /tmp/cutter-self-test.log --args --self-test
enum CommandLineTool {
    /// Returns an exit code when the arguments asked for a terminal task, or nil to start
    /// the app as usual.
    static func run(_ arguments: [String]) -> Int32? {
        switch arguments.first {
        case "--diagnose":
            diagnose()
            return 0
        case "--login-item":
            return loginItem(arguments.dropFirst().first)
        case "--self-test":
            return SelfTest.run()
        case "--self-test-window":
            return SelfTest.runWindowHost(screenIndex: arguments.dropFirst().first)
        case "--help", "-h":
            print("usage: Cutter [--diagnose | --self-test | --login-item status|on|off]")
            return 0
        #if DEBUG
        case "--snapshot-settings":
            return snapshotSettings(to: arguments.dropFirst().first)
        #endif
        default:
            return nil
        }
    }

    /// Prints what Cutter sees, and checks that macOS accepts each configured shortcut by
    /// registering it and releasing it again at once.
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

        let configuration = ShortcutStore().load()
        let hotKeys = HotKeyCenter()
        let failures = hotKeys.register(configuration.assignments)
        hotKeys.unregisterAll()

        print("Shortcuts:")
        for action in WindowAction.allCases {
            let title = action.title.padding(toLength: 20, withPad: " ", startingAt: 0)
            guard let combo = configuration.shortcut(for: action) else {
                print("  \(title)-")
                continue
            }
            let shortcut = KeyComboFormatter.string(for: combo).padding(toLength: 8, withPad: " ", startingAt: 0)
            if let status = failures[action] {
                print("  \(title)\(shortcut)macOS refused it (status \(status))")
            } else {
                print("  \(title)\(shortcut)registers")
            }
        }
    }

    private static func loginItem(_ argument: String?) -> Int32 {
        do {
            switch argument {
            case "on":
                try SMAppService.mainApp.register()
            case "off":
                try SMAppService.mainApp.unregister()
            case "status", nil:
                break
            default:
                print("usage: Cutter --login-item status|on|off")
                return 2
            }
        } catch {
            print("Failed: \(error.localizedDescription)")
            print("Launch at login: \(LoginItem.describe(SMAppService.mainApp.status))")
            return 1
        }
        print("Launch at login: \(LoginItem.describe(SMAppService.mainApp.status))")
        return 0
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
            registersHotKeys: false
        )
        let window = SettingsWindowController(model: model).window

        do {
            try snapshot(window, to: "\(directory)/settings-needs-access.png")
            isTrusted = true
            permission.refresh()
            model.setShortcut(KeyCombo(keyCode: KeyCode.returnKey, modifiers: [.control, .option]), for: .toggleFullScreen)
            try snapshot(window, to: "\(directory)/settings-access-allowed.png")
        } catch {
            print("Failed: \(error.localizedDescription)")
            return 1
        }
        return 0
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
