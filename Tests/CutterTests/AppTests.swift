import AppKit
import Carbon.HIToolbox
import Testing

@testable import Cutter
import CutterCore

/// A model that keeps its settings in memory and never registers a global shortcut, so the
/// tests cannot take keys away from whoever is using this Mac.
@MainActor
private func makeModel(
    storage: InMemoryShortcutStorage = InMemoryShortcutStorage(),
    isTrusted: Bool = true
) -> AppModel {
    AppModel(
        store: ShortcutStore(storage: storage),
        permission: AccessibilityPermission { isTrusted },
        registersHotKeys: false
    )
}

private func keyDown(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
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

private let keyT: UInt16 = 17

@MainActor
@Suite struct ShortcutRecorderTests {
    private func makeRecorder() -> ShortcutRecorder {
        let recorder = ShortcutRecorder()
        recorder.onRejectedKey = {}
        return recorder
    }

    @Test func recordsAKeyWithModifiers() {
        let recorder = makeRecorder()
        var committed: [KeyCombo?] = []
        recorder.toggle(for: .topHalf) { committed.append($0) }
        #expect(recorder.recordingAction == .topHalf)

        let passedOn = recorder.handle(keyDown(keyT, [.command, .shift]))
        #expect(passedOn == nil)
        #expect(committed == [KeyCombo(keyCode: keyT, modifiers: [.command, .shift])])
        #expect(recorder.recordingAction == nil)
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
        #expect(secondLaunch.configuration.shortcut(for: .maximize) == KeyCombo(keyCode: KeyCode.returnKey, modifiers: [.control, .option]))
    }

    @Test func takingAnotherActionsShortcutIsExplained() {
        let model = makeModel()
        model.setShortcut(KeyCombo(keyCode: KeyCode.returnKey, modifiers: [.control, .option]), for: .toggleFullScreen)
        #expect(model.configuration.shortcut(for: .maximize) == nil)
        #expect(model.notice == "⌃⌥↩ now triggers Toggle Full Screen instead of Maximize.")

        model.resetToDefaults()
        #expect(model.notice == nil)
        #expect(model.configuration.isDefault)
    }
}

@MainActor
@Suite struct StatusMenuTests {
    private func menu(for model: AppModel) -> NSMenu {
        let menu = NSMenu()
        StatusMenuController(model: model) {}.menuNeedsUpdate(menu)
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

        let bottomHalf = try #require(menu.item(withTitle: "Bottom Half"))
        #expect(bottomHalf.keyEquivalent.unicodeScalars.first?.value == UInt32(NSDownArrowFunctionKey))
        #expect(bottomHalf.keyEquivalentModifierMask == [.control, .option])

        #expect(try #require(menu.item(withTitle: "Top Left")).keyEquivalent == "")
        #expect(try #require(menu.item(withTitle: "Toggle Full Screen")).keyEquivalent == "")
        #expect(menu.item(withTitle: "Settings…") != nil)
        #expect(menu.item(withTitle: "Quit Cutter") != nil)
        #expect(menu.item(withTitle: "Allow Accessibility Access…") == nil)
    }

    @Test func withoutAccessibilityAccessActionsAreDisabledAndTheMenuSaysWhy() throws {
        let menu = menu(for: makeModel(isTrusted: false))
        #expect(menu.items.first?.title == "Allow Accessibility Access…")
        for action in WindowAction.allCases {
            #expect(try #require(menu.item(withTitle: action.title)).isEnabled == false)
        }
        #expect(try #require(menu.item(withTitle: "Settings…")).isEnabled)
    }
}

@Suite struct KeyComboFormatterTests {
    @Test func defaultShortcutsReadAsInMenus() {
        let expected: [WindowAction: String] = [
            .maximize: "⌃⌥↩",
            .leftHalf: "⌃⌥←",
            .rightHalf: "⌃⌥→",
            .topHalf: "⌃⌥↑",
            .bottomHalf: "⌃⌥↓",
        ]
        let defaults = ShortcutConfiguration.defaultShortcuts
        #expect(defaults.count == expected.count)
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
