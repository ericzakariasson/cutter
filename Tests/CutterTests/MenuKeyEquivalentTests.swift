import AppKit
import Testing

@testable import Cutter
import CutterCore

private final class RecordingHotKeys: HotKeyRegistering {
    var onHotKey: ((WindowAction) -> Void)?
    private(set) var registered: [WindowAction: KeyCombo] = [:]

    func register(_ assignments: [(action: WindowAction, combo: KeyCombo)]) -> [WindowAction: OSStatus] {
        registered = Dictionary(uniqueKeysWithValues: assignments.map { ($0.action, $0.combo) })
        return [:]
    }

    func unregisterAll() {
        registered = [:]
    }
}

/// A key a user can record that is not a letter, digit or punctuation key.
private struct SpecialKey: CustomTestStringConvertible, Sendable {
    let name: String
    let keyCode: UInt16
    /// The character AppKit documents for this key in a menu item's key equivalent.
    let menuKeyEquivalent: UInt32
    /// How Settings and the recorder show the key.
    let label: String
    /// Flags the system adds to this key's events besides the modifiers held.
    var eventFlags: CGEventFlags = []

    var testDescription: String { name }
}

private let functionKey: CGEventFlags = .maskSecondaryFn
private let arrowKey: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]

private let specialKeys: [SpecialKey] = [
    SpecialKey(name: "Return", keyCode: KeyCode.returnKey, menuKeyEquivalent: 0x0D, label: "↩"),
    SpecialKey(name: "Keypad Enter", keyCode: KeyCode.keypadEnter, menuKeyEquivalent: 0x03, label: "⌅", eventFlags: .maskNumericPad),
    SpecialKey(name: "Tab", keyCode: KeyCode.tab, menuKeyEquivalent: 0x09, label: "⇥"),
    SpecialKey(name: "Space", keyCode: KeyCode.space, menuKeyEquivalent: 0x20, label: "Space"),
    // Not the characters the key events carry: AppKit documents 0x08 for Delete and
    // 0x7F for Forward Delete in a menu item.
    SpecialKey(name: "Delete", keyCode: KeyCode.delete, menuKeyEquivalent: 0x08, label: "⌫"),
    SpecialKey(name: "Forward Delete", keyCode: KeyCode.forwardDelete, menuKeyEquivalent: 0x7F, label: "⌦", eventFlags: functionKey),
    SpecialKey(name: "Escape", keyCode: KeyCode.escape, menuKeyEquivalent: 0x1B, label: "⎋"),
    SpecialKey(name: "Up", keyCode: KeyCode.upArrow, menuKeyEquivalent: 0xF700, label: "↑", eventFlags: arrowKey),
    SpecialKey(name: "Down", keyCode: KeyCode.downArrow, menuKeyEquivalent: 0xF701, label: "↓", eventFlags: arrowKey),
    SpecialKey(name: "Left", keyCode: KeyCode.leftArrow, menuKeyEquivalent: 0xF702, label: "←", eventFlags: arrowKey),
    SpecialKey(name: "Right", keyCode: KeyCode.rightArrow, menuKeyEquivalent: 0xF703, label: "→", eventFlags: arrowKey),
    SpecialKey(name: "Home", keyCode: KeyCode.home, menuKeyEquivalent: 0xF729, label: "↖", eventFlags: functionKey),
    SpecialKey(name: "End", keyCode: KeyCode.end, menuKeyEquivalent: 0xF72B, label: "↘", eventFlags: functionKey),
    SpecialKey(name: "Page Up", keyCode: KeyCode.pageUp, menuKeyEquivalent: 0xF72C, label: "⇞", eventFlags: functionKey),
    SpecialKey(name: "Page Down", keyCode: KeyCode.pageDown, menuKeyEquivalent: 0xF72D, label: "⇟", eventFlags: functionKey),
    SpecialKey(name: "F1", keyCode: 122, menuKeyEquivalent: 0xF704, label: "F1", eventFlags: functionKey),
    SpecialKey(name: "F5", keyCode: 96, menuKeyEquivalent: 0xF708, label: "F5", eventFlags: functionKey),
    SpecialKey(name: "F12", keyCode: 111, menuKeyEquivalent: 0xF70F, label: "F12", eventFlags: functionKey),
    SpecialKey(name: "F13", keyCode: 105, menuKeyEquivalent: 0xF710, label: "F13", eventFlags: functionKey),
    SpecialKey(name: "F20", keyCode: 90, menuKeyEquivalent: 0xF717, label: "F20", eventFlags: functionKey),
]

private let keypadOne: UInt16 = 83
private let mainRowOne: UInt16 = 18
private let controlOption: KeyCombo.Modifiers = [.control, .option]

/// A key-down event as the system builds one for a key press: the characters come from
/// the key code and the keyboard layout. It is only handed to the menu in this process,
/// never posted, so nothing reaches the apps on this Mac.
private func keyPress(_ keyCode: UInt16, _ extraFlags: CGEventFlags = []) throws -> NSEvent {
    let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
    event.flags = CGEventFlags([.maskControl, .maskAlternate]).union(extraFlags)
    return try #require(NSEvent(cgEvent: event))
}

/// Cutter's menu with one shortcut, ⌃⌥ plus the given key on Maximize, and nothing else.
@MainActor
private final class MenuHarness {
    let model: AppModel
    let hotKeys = RecordingHotKeys()
    let menu = NSMenu()
    private(set) var performed: [WindowAction] = []
    private var controller: StatusMenuController?
    private var eventBeingHandled: NSEvent?

    init(shortcutKey keyCode: UInt16) {
        // Sending a menu item's action goes through the application object.
        _ = NSApplication.shared

        var record: (WindowAction) -> Void = { _ in }
        model = AppModel(
            store: ShortcutStore(storage: InMemoryShortcutStorage()),
            permission: AccessibilityPermission { true },
            hotKeys: hotKeys,
            act: { record($0) }
        )
        record = { [unowned self] in performed.append($0) }

        for action in WindowAction.allCases {
            model.setShortcut(nil, for: action)
        }
        model.setShortcut(KeyCombo(keyCode: keyCode, modifiers: controlOption), for: .maximize)

        let controller = StatusMenuController(
            model: model,
            screenCount: { 2 },
            currentEvent: { [unowned self] in eventBeingHandled },
            showSettings: {}
        )
        self.controller = controller
        menu.autoenablesItems = false
        controller.menuNeedsUpdate(menu)
    }

    var maximizeItem: NSMenuItem {
        menu.item(withTitle: "Maximize")!
    }

    /// Whether pressing the key while the menu is open runs Maximize.
    func runsMaximize(_ event: NSEvent) -> Bool {
        performed = []
        eventBeingHandled = event
        defer { eventBeingHandled = nil }
        _ = menu.performKeyEquivalent(with: event)
        return performed == [.maximize]
    }
}

@MainActor
@Suite struct MenuKeyEquivalentTests {
    @Test(arguments: specialKeys)
    fileprivate func theMenuItemHoldsTheDocumentedCharacter(key: SpecialKey) {
        let equivalent = KeyComboFormatter.menuKeyEquivalent(for: key.keyCode)
        #expect(equivalent?.unicodeScalars.map(\.value) == [key.menuKeyEquivalent])

        let item = MenuHarness(shortcutKey: key.keyCode).maximizeItem
        #expect(item.keyEquivalent.unicodeScalars.map(\.value) == [key.menuKeyEquivalent])
        #expect(item.keyEquivalentModifierMask == [.control, .option])
    }

    @Test func theArrowKeysUseTheFunctionKeyCharactersNotTheOldControlCharacters() {
        let arrows = [KeyCode.upArrow, KeyCode.downArrow, KeyCode.leftArrow, KeyCode.rightArrow]
        let scalars = arrows.compactMap { KeyComboFormatter.menuKeyEquivalent(for: $0)?.unicodeScalars.first?.value }
        #expect(scalars == [0xF700, 0xF701, 0xF702, 0xF703])
        #expect(scalars == [NSUpArrowFunctionKey, NSDownArrowFunctionKey, NSLeftArrowFunctionKey, NSRightArrowFunctionKey].map(UInt32.init))
    }

    /// With the menu open the global shortcuts are off, so the menu item has to answer
    /// to the key itself, and to no other key in the list.
    @Test(arguments: specialKeys)
    fileprivate func pressingTheKeyWithTheMenuOpenRunsItsActionAndOnlyThatKeyDoes(key: SpecialKey) throws {
        let harness = MenuHarness(shortcutKey: key.keyCode)
        #expect(harness.runsMaximize(try keyPress(key.keyCode, key.eventFlags)))

        for other in specialKeys where other.keyCode != key.keyCode {
            let ran = harness.runsMaximize(try keyPress(other.keyCode, other.eventFlags))
            #expect(!ran, "\(other.name) must not trigger a shortcut on \(key.name)")
        }
    }

    @Test(arguments: specialKeys)
    fileprivate func settingsAndTheRecorderShowTheKeyTheSameWay(key: SpecialKey) {
        #expect(KeyComboFormatter.keyName(for: key.keyCode) == key.label)
        #expect(KeyComboFormatter.string(for: KeyCombo(keyCode: key.keyCode, modifiers: controlOption)) == "⌃⌥" + key.label)
    }

    @Test func aLetterKeyWorksWithTheMenuOpen() throws {
        let keyT: UInt16 = 17
        let harness = MenuHarness(shortcutKey: keyT)
        #expect(harness.runsMaximize(try keyPress(keyT)))
        #expect(!harness.runsMaximize(try keyPress(16)))
    }
}

@MainActor
@Suite struct KeypadShortcutTests {
    @Test func aKeypadDigitIsToldApartFromTheMainRowDigitInSettings() {
        #expect(KeyComboFormatter.keyName(for: keypadOne) == "Keypad 1")
        #expect(KeyComboFormatter.keyName(for: mainRowOne) == "1")
        #expect(KeyComboFormatter.keyName(for: 69) == "Keypad +")
    }

    /// A menu key equivalent is a character, so "1" matches both keys. Only the key the
    /// shortcut was recorded with may run the action.
    @Test func aKeypadShortcutIsNotTriggeredByTheMainRowKey() throws {
        let harness = MenuHarness(shortcutKey: keypadOne)
        #expect(harness.maximizeItem.keyEquivalent == "1")
        #expect(harness.runsMaximize(try keyPress(keypadOne, .maskNumericPad)))
        #expect(!harness.runsMaximize(try keyPress(mainRowOne)))
    }

    @Test func aMainRowShortcutIsNotTriggeredByTheKeypadKey() throws {
        let harness = MenuHarness(shortcutKey: mainRowOne)
        #expect(harness.runsMaximize(try keyPress(mainRowOne)))
        #expect(!harness.runsMaximize(try keyPress(keypadOne, .maskNumericPad)))
    }

    @Test func choosingAnItemWithTheMouseAlwaysRunsIt() throws {
        let harness = MenuHarness(shortcutKey: keypadOne)
        let item = harness.maximizeItem
        // No key event is being handled when an item is clicked.
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        #expect(harness.performed == [.maximize])
    }

    /// Keypad Clear and Help have no menu key equivalent, so the menu cannot answer to
    /// them. Their global shortcut stays registered while the menu is open instead.
    @Test(arguments: [KeyCode.keypadClear, KeyCode.help])
    func aKeyTheMenuCannotExpressKeepsItsGlobalShortcutWhileTheMenuIsOpen(keyCode: UInt16) {
        #expect(KeyComboFormatter.menuKeyEquivalent(for: keyCode) == nil)

        let harness = MenuHarness(shortcutKey: keyCode)
        let combo = KeyCombo(keyCode: keyCode, modifiers: controlOption)
        #expect(harness.maximizeItem.keyEquivalent == "")
        #expect(harness.hotKeys.registered == [.maximize: combo])

        harness.model.menuDidOpen()
        #expect(harness.hotKeys.registered == [.maximize: combo])
        harness.model.menuDidClose()
        #expect(harness.hotKeys.registered == [.maximize: combo])
    }

    @Test func aKeyTheMenuAnswersToGivesUpItsGlobalShortcutWhileTheMenuIsOpen() {
        let harness = MenuHarness(shortcutKey: KeyCode.leftArrow)
        harness.model.menuDidOpen()
        #expect(harness.hotKeys.registered.isEmpty)
        harness.model.menuDidClose()
        #expect(harness.hotKeys.registered.count == 1)
    }

    @Test func clearAndHelpHaveNames() {
        #expect(KeyComboFormatter.keyName(for: KeyCode.keypadClear) == "⌧")
        #expect(KeyComboFormatter.keyName(for: KeyCode.help) == "Help")
    }
}
