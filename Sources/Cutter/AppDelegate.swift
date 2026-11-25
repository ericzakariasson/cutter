import AppKit
import ApplicationServices

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var settings: SettingsWindowController?
    private var statusMenu: StatusMenuController?
    private let screenshots = ScreenshotPanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAnotherInstanceRunning() {
            NSLog(
                "Cutter %@: already running, quitting this copy. Accessibility access: %@.",
                AppInfo.version,
                AXIsProcessTrusted() ? "allowed" : "not allowed yet"
            )
            NSApp.terminate(nil)
            return
        }

        NSApp.mainMenu = makeMainMenu()

        let model = AppModel()
        let settings = SettingsWindowController(model: model)
        model.showSettings = { [weak settings] in
            settings?.show(activating: true)
        }
        model.toggleRecentScreenshots = { [screenshots] in
            screenshots.toggle()
        }
        let statusMenu = StatusMenuController(model: model) { [weak settings] in
            settings?.show(activating: true)
        }
        statusMenu.install()
        self.model = model
        self.settings = settings
        self.statusMenu = statusMenu

        NSLog(
            "Cutter %@ started. Accessibility access: %@.",
            AppInfo.version,
            model.permission.isTrusted ? "allowed" : "not allowed yet"
        )
        // The menu bar lays the icon out a moment after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak statusMenu] in
            NSLog("Cutter: menu bar icon %@", statusMenu?.placementDescription ?? "not shown")
        }

        if !model.permission.isTrusted {
            // First run: explain the permission. Do not grab keyboard focus; the user did
            // not necessarily launch Cutter by hand (login item).
            settings.show(activating: false)
        }
    }

    /// Opening Cutter again while it runs (Finder, Spotlight, `open`) shows its settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settings?.show(activating: true)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func showSettings() {
        settings?.show(activating: true)
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { $0.processIdentifier != ownPID }
    }

    /// A menu bar app shows no main menu, but without one the settings window would not
    /// respond to ⌘W, ⌘M, ⌘, or ⌘Q.
    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Cutter", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Cutter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(withTitle: "Cutter", action: nil, keyEquivalent: "").submenu = appMenu

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        mainMenu.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu

        return mainMenu
    }
}
