import AppKit
import CutterCore

/// The menu bar item: every action, with its shortcut, plus Settings and Quit.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let showSettings: () -> Void
    private var statusItem: NSStatusItem?

    init(model: AppModel, showSettings: @escaping () -> Void) {
        self.model = model
        self.showSettings = showSettings
        super.init()
    }

    /// Puts the icon in the menu bar.
    func install() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "rectangle.lefthalf.inset.filled",
                accessibilityDescription: "Cutter"
            )
            image?.isTemplate = true
            button.image = image
            if image == nil {
                button.title = "Cutter"
            }
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    /// For the log: where the icon sits, or that macOS is not showing it.
    var placementDescription: String {
        guard let statusItem, statusItem.isVisible, let frame = statusItem.button?.window?.frame else {
            return "not shown"
        }
        return "shown at x \(Int(frame.minX))"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let isTrusted = model.permission.isTrusted

        if !isTrusted {
            menu.addItem(makeItem("Allow Accessibility Access…", action: #selector(openSettings)))
            menu.addItem(.separator())
        }

        for action in WindowAction.allCases {
            if action == .toggleFullScreen {
                menu.addItem(.separator())
            }
            let item = makeItem(action.title, action: #selector(performAction(_:)))
            item.representedObject = action.rawValue
            item.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)
            item.isEnabled = isTrusted
            if let combo = model.configuration.shortcut(for: action),
               let keyEquivalent = KeyComboFormatter.menuKeyEquivalent(for: combo.keyCode) {
                item.keyEquivalent = keyEquivalent
                item.keyEquivalentModifierMask = combo.modifiers.eventFlags
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let settings = makeItem("Settings…", action: #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Cutter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = WindowAction(rawValue: rawValue)
        else {
            return
        }
        model.perform(action)
    }

    @objc private func openSettings() {
        showSettings()
    }
}
