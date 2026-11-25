import AppKit
import CutterCore

/// The menu bar item: every action, with its shortcut, plus Settings and Quit.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let showSettings: () -> Void
    private let screenCount: () -> Int
    private let currentEvent: () -> NSEvent?
    private var statusItem: NSStatusItem?

    /// - Parameter currentEvent: the event being handled when a menu item's action runs.
    init(
        model: AppModel,
        screenCount: @escaping () -> Int = { NSScreen.screens.count },
        currentEvent: @escaping () -> NSEvent? = { NSApp.currentEvent },
        showSettings: @escaping () -> Void
    ) {
        self.model = model
        self.screenCount = screenCount
        self.currentEvent = currentEvent
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

    func menuWillOpen(_ menu: NSMenu) {
        model.menuDidOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        model.menuDidClose()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let isTrusted = model.permission.isTrusted

        if !isTrusted {
            menu.addItem(makeItem("Allow Accessibility Access…", action: #selector(openSettings)))
            menu.addItem(.separator())
        }

        for action in WindowAction.allCases {
            if action == .previousDisplay || action == .toggleFullScreen || action == .recentScreenshots {
                menu.addItem(.separator())
            }
            let item = makeItem(action.title, action: #selector(performAction(_:)))
            item.representedObject = action.rawValue
            item.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)
            item.isEnabled = (isTrusted || !action.needsAccessibility)
                && (!action.movesBetweenDisplays || screenCount() > 1)
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
        if let event = currentEvent(), let combo = model.configuration.shortcut(for: action),
           Self.isShortcutOnAnotherKey(event, for: combo) {
            return
        }
        model.perform(action)
    }

    /// A menu key equivalent is a character, so an item also fires for another key that
    /// types the same one: the main 1 for a shortcut on the keypad's 1. That press is not
    /// the shortcut. Choosing the item with the mouse, or with the arrow keys and Return,
    /// is something else and always runs it.
    static func isShortcutOnAnotherKey(_ event: NSEvent, for combo: KeyCombo) -> Bool {
        guard event.type == .keyDown, event.keyCode != combo.keyCode else {
            return false
        }
        return KeyCombo.Modifiers(event.modifierFlags) == combo.modifiers
            && KeyComboFormatter.menuKeyEquivalent(for: event.keyCode) == KeyComboFormatter.menuKeyEquivalent(for: combo.keyCode)
    }

    @objc private func openSettings() {
        showSettings()
    }
}
