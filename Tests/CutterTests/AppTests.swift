import AppKit
import Carbon.HIToolbox
import Testing

@testable import Cutter
import CutterCore

/// Stands in for the real hot key registration, so the tests never take a key away from
/// whoever is using this Mac. It records what would be registered.
private final class FakeHotKeys: HotKeyRegistering {
    var onHotKey: ((WindowAction) -> Void)?
    var rejecting: [WindowAction: OSStatus] = [:]
    private(set) var registered: [WindowAction: KeyCombo] = [:]

    func register(_ assignments: [(action: WindowAction, combo: KeyCombo)]) -> [WindowAction: OSStatus] {
        registered = [:]
        var failures: [WindowAction: OSStatus] = [:]
        for (action, combo) in assignments {
            if let status = rejecting[action] {
                failures[action] = status
            } else {
                registered[action] = combo
            }
        }
        return failures
    }

    func unregisterAll() {
        registered = [:]
    }
}

/// A model that keeps its settings in memory, registers nothing with macOS, and hands
/// actions to `act` instead of moving a window.
@MainActor
private func makeModel(
    storage: InMemoryShortcutStorage = InMemoryShortcutStorage(),
    hotKeys: FakeHotKeys = FakeHotKeys(),
    act: @escaping (WindowAction) throws -> Void = { _ in },
    isTrusted: @escaping () -> Bool = { true }
) -> AppModel {
    AppModel(
        store: ShortcutStore(storage: storage),
        permission: AccessibilityPermission(check: isTrusted),
        hotKeys: hotKeys,
        act: act
    )
}

private func keyEvent(_ type: NSEvent.EventType, _ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(
        with: type,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: keyCode
    )!
}

private func keyDown(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    keyEvent(.keyDown, keyCode, modifiers)
}

// Key positions on a US keyboard.
private let keyA: UInt16 = 0
private let keyC: UInt16 = 8
private let keyQ: UInt16 = 12
private let keyT: UInt16 = 17
private let usLayout: [UInt16: String] = [keyA: "a", keyC: "c", keyQ: "q", keyT: "t"]

private let controlOption: KeyCombo.Modifiers = [.control, .option]
private let defaultCount = ShortcutConfiguration.defaultShortcuts.count
private let screenshotsShortcutOnly: [WindowAction: KeyCombo] = [
    .recentScreenshots: KeyCombo(keyCode: KeyCode.s, modifiers: controlOption),
]
private let controlOptionReturn = KeyCombo(keyCode: KeyCode.returnKey, modifiers: controlOption)

@MainActor
@Suite struct ShortcutRecorderTests {
    private func makeRecorder(layout: [UInt16: String] = usLayout) -> ShortcutRecorder {
        let recorder = ShortcutRecorder()
        recorder.onRejectedKey = {}
        recorder.characterForKeyCode = { layout[$0] }
        return recorder
    }

    @Test func recordsAKeyWithModifiers() {
        let recorder = makeRecorder()
        var committed: [KeyCombo?] = []
        recorder.toggle(for: .topHalf) { committed.append($0) }
        #expect(recorder.recordingAction == .topHalf)

        let passedOn = recorder.handle(keyDown(keyT, [.control, .option]))
        #expect(passedOn == nil)
        #expect(committed == [KeyCombo(keyCode: keyT, modifiers: controlOption)])
        #expect(recorder.recordingAction == nil)
        #expect(recorder.warning == nil)
    }

    @Test func rejectsAKeyWithoutARealModifierAndKeepsRecording() {
        let recorder = makeRecorder()
        var committed: [KeyCombo?] = []
        var rejections = 0
        recorder.onRejectedKey = { rejections += 1 }
        recorder.toggle(for: .topHalf) { committed.append($0) }

        #expect(recorder.handle(keyDown(keyT)) == nil)
        #expect(recorder.handle(keyDown(keyT, [.shift])) == nil)
        #expect(committed.isEmpty)
        #expect(rejections == 2)
        #expect(recorder.recordingAction == .topHalf)
        #expect(recorder.hint != nil)
        recorder.cancel()
    }

    @Test func escapeCancelsAndDeleteClears() {
        let recorder = makeRecorder()
        var committed: [KeyCombo?] = []

        recorder.toggle(for: .maximize) { committed.append($0) }
        #expect(recorder.handle(keyDown(KeyCode.escape)) == nil)
        #expect(recorder.recordingAction == nil)
        #expect(committed.isEmpty)

        recorder.toggle(for: .maximize) { committed.append($0) }
        #expect(recorder.handle(keyDown(KeyCode.delete)) == nil)
        #expect(recorder.recordingAction == nil)
        #expect(committed.count == 1)
        #expect(committed.first == .some(nil))
    }

    @Test func clickingTheSameFieldAgainStopsRecordingAndAnotherFieldTakesOver() {
        let recorder = makeRecorder()
        recorder.toggle(for: .maximize) { _ in }
        recorder.toggle(for: .maximize) { _ in }
        #expect(recorder.recordingAction == nil)

        recorder.toggle(for: .maximize) { _ in }
        recorder.toggle(for: .leftHalf) { _ in }
        #expect(recorder.recordingAction == .leftHalf)
        recorder.cancel()
    }

    @Test func aWellKnownShortcutIsOnlyAcceptedWhenPressedTwice() throws {
        let recorder = makeRecorder()
        var committed: [KeyCombo?] = []
        recorder.toggle(for: .maximize) { committed.append($0) }

        #expect(recorder.handle(keyDown(keyQ, [.command])) == nil)
        #expect(committed.isEmpty)
        #expect(recorder.recordingAction == .maximize)
        #expect(try #require(recorder.warning).contains("usually quits the app"))
        #expect(recorder.hint == "Again to confirm")

        // Letting go of ⌘ must not wipe the request to confirm.
        _ = recorder.handle(keyEvent(.flagsChanged, 55, []))
        #expect(recorder.hint == "Again to confirm")
        #expect(recorder.warning != nil)

        #expect(recorder.handle(keyDown(keyQ, [.command])) == nil)
        #expect(committed == [KeyCombo(keyCode: keyQ, modifiers: [.command])])
        #expect(recorder.recordingAction == nil)
        #expect(recorder.warning == nil)
    }

    @Test func afterAWarningOtherKeysAreJudgedOnTheirOwn() throws {
        let recorder = makeRecorder()
        var committed: [KeyCombo?] = []
        recorder.toggle(for: .maximize) { committed.append($0) }

        _ = recorder.handle(keyDown(keyQ, [.command]))
        // Another well-known shortcut gets its own warning rather than counting as the confirmation.
        _ = recorder.handle(keyDown(keyC, [.command]))
        #expect(committed.isEmpty)
        #expect(try #require(recorder.warning).contains("usually copies"))

        // An ordinary shortcut is recorded at once.
        _ = recorder.handle(keyDown(keyT, [.control, .option]))
        #expect(committed == [KeyCombo(keyCode: keyT, modifiers: controlOption)])
        #expect(recorder.warning == nil)
    }

    @Test func escapeAfterAWarningRecordsNothing() {
        let recorder = makeRecorder()
        var committed: [KeyCombo?] = []
        recorder.toggle(for: .maximize) { committed.append($0) }

        _ = recorder.handle(keyDown(keyQ, [.command]))
        _ = recorder.handle(keyDown(KeyCode.escape))
        #expect(committed.isEmpty)
        #expect(recorder.recordingAction == nil)
        #expect(recorder.warning == nil)
    }

    @Test func theFirstDefaultsNowAskFirst() throws {
        // ⌘↩ and ⇧⌘← were Cutter's first defaults and got in the way of other apps.
        let recorder = makeRecorder()
        var committed: [KeyCombo?] = []
        recorder.toggle(for: .maximize) { committed.append($0) }

        _ = recorder.handle(keyDown(KeyCode.returnKey, [.command]))
        #expect(try #require(recorder.warning).contains("sends or submits"))
        _ = recorder.handle(keyDown(KeyCode.leftArrow, [.command, .shift]))
        #expect(try #require(recorder.warning).contains("selects to the start or end of the line"))
        #expect(committed.isEmpty)
        recorder.cancel()
    }

    @Test func lettersFollowTheKeyboardLayout() throws {
        // On a French keyboard the key in the US Q position types A.
        let recorder = makeRecorder(layout: [keyQ: "a", keyA: "q"])
        var committed: [KeyCombo?] = []
        recorder.toggle(for: .maximize) { committed.append($0) }

        _ = recorder.handle(keyDown(keyQ, [.command]))
        #expect(try #require(recorder.warning).contains("selects everything"))
        _ = recorder.handle(keyDown(keyA, [.command]))
        #expect(try #require(recorder.warning).contains("quits the app"))
        #expect(committed.isEmpty)
        recorder.cancel()
    }

    @Test func theDefaultShortcutsAreRecordedWithoutAWarning() {
        for (action, combo) in ShortcutConfiguration.defaultShortcuts {
            let recorder = makeRecorder()
            var committed: [KeyCombo?] = []
            recorder.toggle(for: action) { committed.append($0) }
            _ = recorder.handle(keyDown(combo.keyCode, combo.modifiers.eventFlags))
            #expect(committed == [combo])
        }
    }
}

@MainActor
@Suite struct AppModelTests {
    @Test func changesAreSavedAndLoadedByTheNextLaunch() {
        let storage = InMemoryShortcutStorage()
        let commandOptionT = KeyCombo(keyCode: keyT, modifiers: [.command, .option])

        let firstLaunch = makeModel(storage: storage)
        firstLaunch.setShortcut(commandOptionT, for: .topLeft)
        firstLaunch.setShortcut(nil, for: .rightHalf)

        let secondLaunch = makeModel(storage: storage)
        #expect(secondLaunch.configuration.shortcut(for: .topLeft) == commandOptionT)
        #expect(secondLaunch.configuration.shortcut(for: .rightHalf) == nil)
        #expect(secondLaunch.configuration.shortcut(for: .maximize) == controlOptionReturn)
    }

    @Test func takingAnotherActionsShortcutIsExplained() {
        let model = makeModel()
        model.setShortcut(controlOptionReturn, for: .toggleFullScreen)
        #expect(model.configuration.shortcut(for: .maximize) == nil)
        #expect(model.notice == "⌃⌥↩ now triggers Toggle Full Screen instead of Maximize.")

        model.resetToDefaults()
        #expect(model.notice == nil)
        #expect(model.configuration.isDefault)
    }
}

@MainActor
@Suite struct GlobalShortcutLifecycleTests {
    /// Without Accessibility access a window shortcut would swallow its keys and do
    /// nothing. Showing the screenshots needs no such access, so its shortcut stays live.
    @Test func windowShortcutsAreRegisteredOnlyWhileAccessibilityAccessIsGranted() {
        let hotKeys = FakeHotKeys()
        var isTrusted = false
        let model = makeModel(hotKeys: hotKeys) { isTrusted }
        #expect(hotKeys.registered == screenshotsShortcutOnly)

        isTrusted = true
        model.permission.refresh()
        #expect(hotKeys.registered == ShortcutConfiguration.defaultShortcuts)

        isTrusted = false
        model.permission.refresh()
        #expect(hotKeys.registered == screenshotsShortcutOnly)
    }

    @Test func aChangedShortcutIsRegisteredAtOnce() {
        let hotKeys = FakeHotKeys()
        let model = makeModel(hotKeys: hotKeys)
        let combo = KeyCombo(keyCode: keyT, modifiers: controlOption)

        model.setShortcut(combo, for: .topLeft)
        #expect(hotKeys.registered[.topLeft] == combo)

        model.setShortcut(nil, for: .maximize)
        #expect(hotKeys.registered[.maximize] == nil)
        #expect(hotKeys.registered.count == defaultCount)
    }

    @Test func recordingPausesTheShortcuts() {
        let hotKeys = FakeHotKeys()
        let model = makeModel(hotKeys: hotKeys)

        model.recorder.toggle(for: .maximize) { _ in }
        #expect(hotKeys.registered.isEmpty)

        model.recorder.cancel()
        #expect(hotKeys.registered == ShortcutConfiguration.defaultShortcuts)
    }

    /// The menu items answer to the same keys as the global shortcuts. With both live, one
    /// key press could run an action twice, and Toggle Full Screen would undo itself.
    @Test func theOpenMenuTakesOverFromTheGlobalShortcuts() {
        let hotKeys = FakeHotKeys()
        let model = makeModel(hotKeys: hotKeys)
        let controller = StatusMenuController(model: model) {}
        let menu = NSMenu()
        #expect(hotKeys.registered.count == defaultCount)

        controller.menuWillOpen(menu)
        #expect(hotKeys.registered.isEmpty)

        // Settings changed while the menu is open do not bring them back early.
        model.setShortcut(KeyCombo(keyCode: keyT, modifiers: controlOption), for: .topLeft)
        #expect(hotKeys.registered.isEmpty)

        controller.menuDidClose(menu)
        #expect(hotKeys.registered.count == defaultCount + 1)
    }

    @Test func closingTheMenuDoesNotRegisterWindowShortcutsWithoutAccess() {
        let hotKeys = FakeHotKeys()
        let model = makeModel(hotKeys: hotKeys) { false }
        model.menuDidOpen()
        #expect(hotKeys.registered.isEmpty)
        model.menuDidClose()
        #expect(hotKeys.registered == screenshotsShortcutOnly)
    }

    @Test func theScreenshotsShortcutShowsThePanelAndMovesNoWindow() {
        let hotKeys = FakeHotKeys()
        var performed: [WindowAction] = []
        var toggles = 0
        let model = makeModel(hotKeys: hotKeys, act: { performed.append($0) })
        model.toggleRecentScreenshots = { toggles += 1 }

        hotKeys.onHotKey?(.recentScreenshots)
        #expect(toggles == 1)
        #expect(performed.isEmpty)
    }

    @Test func aShortcutMacOSRejectsIsReportedWithItsStatus() {
        let hotKeys = FakeHotKeys()
        hotKeys.rejecting = [.maximize: OSStatus(eventHotKeyExistsErr)]
        let model = makeModel(hotKeys: hotKeys)

        #expect(model.failedRegistrations == [.maximize: OSStatus(eventHotKeyExistsErr)])
        #expect(hotKeys.registered.count == defaultCount - 1)

        hotKeys.rejecting = [:]
        model.setShortcut(KeyCombo(keyCode: keyT, modifiers: controlOption), for: .maximize)
        #expect(model.failedRegistrations.isEmpty)
    }

    @Test func aGlobalShortcutRunsItsAction() {
        let hotKeys = FakeHotKeys()
        var performed: [WindowAction] = []
        let model = makeModel(hotKeys: hotKeys, act: { performed.append($0) })

        hotKeys.onHotKey?(.nextDisplay)
        #expect(performed == [.nextDisplay])
        withExtendedLifetime(model) {}
    }

    @Test func anActionThatFindsAccessibilityAccessGoneOpensTheSettings() {
        let hotKeys = FakeHotKeys()
        let model = makeModel(hotKeys: hotKeys, act: { _ in throw WindowManagerError.accessibilityNotGranted })
        var settingsRequests = 0
        model.showSettings = { settingsRequests += 1 }

        hotKeys.onHotKey?(.maximize)
        #expect(settingsRequests == 1)
    }
}

@MainActor
@Suite struct StatusMenuTests {
    private func menu(for model: AppModel, screens: Int = 2) -> NSMenu {
        let menu = NSMenu()
        StatusMenuController(model: model, screenCount: { screens }) {}.menuNeedsUpdate(menu)
        return menu
    }

    @Test func listsEveryActionWithItsShortcut() throws {
        let menu = menu(for: makeModel())
        for action in WindowAction.allCases {
            let item = try #require(menu.item(withTitle: action.title))
            #expect(item.isEnabled)
        }

        let maximize = try #require(menu.item(withTitle: "Maximize"))
        #expect(maximize.keyEquivalent == "\r")
        #expect(maximize.keyEquivalentModifierMask == [.control, .option])

        let leftHalf = try #require(menu.item(withTitle: "Left Half"))
        #expect(leftHalf.keyEquivalent.unicodeScalars.first?.value == UInt32(NSLeftArrowFunctionKey))
        #expect(leftHalf.keyEquivalentModifierMask == [.control, .option])

        let previousDisplay = try #require(menu.item(withTitle: "Move to Previous Display"))
        #expect(previousDisplay.keyEquivalent.unicodeScalars.first?.value == UInt32(NSUpArrowFunctionKey))
        #expect(previousDisplay.keyEquivalentModifierMask == [.control, .option])

        let nextDisplay = try #require(menu.item(withTitle: "Move to Next Display"))
        #expect(nextDisplay.keyEquivalent.unicodeScalars.first?.value == UInt32(NSDownArrowFunctionKey))
        #expect(nextDisplay.keyEquivalentModifierMask == [.control, .option])

        #expect(try #require(menu.item(withTitle: "Top Half")).keyEquivalent == "")
        #expect(try #require(menu.item(withTitle: "Bottom Half")).keyEquivalent == "")
        #expect(try #require(menu.item(withTitle: "Top Left")).keyEquivalent == "")
        #expect(try #require(menu.item(withTitle: "Toggle Full Screen")).keyEquivalent == "")
        #expect(menu.item(withTitle: "Settings…") != nil)
        #expect(menu.item(withTitle: "Quit Cutter") != nil)
        #expect(menu.item(withTitle: "Allow Accessibility Access…") == nil)
    }

    @Test func withOneDisplayTheDisplayMovesAreDisabled() throws {
        let menu = menu(for: makeModel(), screens: 1)
        #expect(try #require(menu.item(withTitle: "Move to Previous Display")).isEnabled == false)
        #expect(try #require(menu.item(withTitle: "Move to Next Display")).isEnabled == false)
        #expect(try #require(menu.item(withTitle: "Maximize")).isEnabled)
    }

    @Test func withoutAccessibilityAccessActionsAreDisabledAndTheMenuSaysWhy() throws {
        let menu = menu(for: makeModel { false })
        #expect(menu.items.first?.title == "Allow Accessibility Access…")
        for action in WindowAction.allCases {
            // Showing the screenshots controls no window, so it stays available.
            #expect(try #require(menu.item(withTitle: action.title)).isEnabled == !action.needsAccessibility)
        }
        #expect(try #require(menu.item(withTitle: "Show Recent Screenshots")).isEnabled)
        #expect(try #require(menu.item(withTitle: "Settings…")).isEnabled)
    }
}

@Suite struct KeyComboFormatterTests {
    @Test func defaultShortcutsReadAsInMenus() {
        let expected: [WindowAction: String] = [
            .maximize: "⌃⌥↩",
            .leftHalf: "⌃⌥←",
            .rightHalf: "⌃⌥→",
            .previousDisplay: "⌃⌥↑",
            .nextDisplay: "⌃⌥↓",
        ]
        // The sixth default, for the screenshots, is a letter key and reads differently
        // on other keyboard layouts.
        let defaults = ShortcutConfiguration.defaultShortcuts
        #expect(defaults.count == expected.count + 1)
        for (action, string) in expected {
            let combo = defaults[action]
            #expect(combo.map(KeyComboFormatter.string(for:)) == string)
        }
        #expect(KeyComboFormatter.string(for: KeyCombo(keyCode: KeyCode.leftArrow, modifiers: [.command, .shift])) == "⇧⌘←")
    }

    @Test func modifiersConvertToCarbonAndBack() {
        let modifiers: KeyCombo.Modifiers = [.command, .shift]
        #expect(modifiers.carbonFlags == UInt32(cmdKey | shiftKey))
        #expect(KeyCombo.Modifiers([.control, .option]).carbonFlags == UInt32(controlKey | optionKey))
        #expect(KeyCombo.Modifiers(modifiers.eventFlags) == modifiers)
        #expect(KeyCombo.Modifiers([.command, .capsLock, .numericPad, .function]) == [.command])
    }
}
