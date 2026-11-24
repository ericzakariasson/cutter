import Foundation
import Testing

@testable import CutterCore

private let controlOption: KeyCombo.Modifiers = [.control, .option]
private let controlOptionReturn = KeyCombo(keyCode: KeyCode.returnKey, modifiers: controlOption)
private let controlOptionLeft = KeyCombo(keyCode: KeyCode.leftArrow, modifiers: controlOption)
private let controlOptionRight = KeyCombo(keyCode: KeyCode.rightArrow, modifiers: controlOption)
private let controlOptionUp = KeyCombo(keyCode: KeyCode.upArrow, modifiers: controlOption)
private let controlOptionDown = KeyCombo(keyCode: KeyCode.downArrow, modifiers: controlOption)
private let commandReturn = KeyCombo(keyCode: KeyCode.returnKey, modifiers: [.command])
private let commandShiftLeft = KeyCombo(keyCode: KeyCode.leftArrow, modifiers: [.command, .shift])
private let commandShiftRight = KeyCombo(keyCode: KeyCode.rightArrow, modifiers: [.command, .shift])
private let commandOptionF = KeyCombo(keyCode: 3, modifiers: [.command, .option])

@Suite struct ShortcutConfigurationTests {
    @Test func defaultsAreControlOptionReturnAndArrows() {
        let configuration = ShortcutConfiguration()
        #expect(configuration.shortcut(for: .maximize) == controlOptionReturn)
        #expect(configuration.shortcut(for: .leftHalf) == controlOptionLeft)
        #expect(configuration.shortcut(for: .rightHalf) == controlOptionRight)
        #expect(configuration.shortcut(for: .topHalf) == controlOptionUp)
        #expect(configuration.shortcut(for: .bottomHalf) == controlOptionDown)

        let assigned = configuration.assignments.map(\.action)
        #expect(assigned == [.maximize, .leftHalf, .rightHalf, .topHalf, .bottomHalf])
        #expect(configuration.isDefault)
    }

    @Test func cornersAndFullScreenHaveNoDefault() {
        let configuration = ShortcutConfiguration()
        for action in [WindowAction.topLeft, .topRight, .bottomLeft, .bottomRight, .toggleFullScreen] {
            #expect(configuration.shortcut(for: action) == nil)
        }
    }

    @Test func noDefaultUsesTheCommandKey() {
        // ⌘↩ and ⇧⌘←/→ were the first defaults and took over keys apps rely on.
        let configuration = ShortcutConfiguration()
        for combo in [commandReturn, commandShiftLeft, commandShiftRight] {
            #expect(configuration.action(for: combo) == nil)
        }
        for (_, combo) in configuration.assignments {
            #expect(!combo.modifiers.contains(.command))
        }
    }

    @Test func assigningAndClearing() {
        var configuration = ShortcutConfiguration()
        #expect(configuration.setShortcut(commandOptionF, for: .toggleFullScreen) == nil)
        #expect(configuration.shortcut(for: .toggleFullScreen) == commandOptionF)
        #expect(configuration.action(for: commandOptionF) == .toggleFullScreen)
        #expect(!configuration.isDefault)

        configuration.setShortcut(nil, for: .maximize)
        #expect(configuration.shortcut(for: .maximize) == nil)
        #expect(configuration.action(for: controlOptionReturn) == nil)
    }

    @Test func aShortcutMovesToTheActionItIsAssignedTo() {
        var configuration = ShortcutConfiguration()
        let displaced = configuration.setShortcut(controlOptionReturn, for: .toggleFullScreen)
        #expect(displaced == .maximize)
        #expect(configuration.shortcut(for: .maximize) == nil)
        #expect(configuration.shortcut(for: .toggleFullScreen) == controlOptionReturn)
        #expect(configuration.action(for: controlOptionReturn) == .toggleFullScreen)
    }

    @Test func reassigningTheSameShortcutDisplacesNothing() {
        var configuration = ShortcutConfiguration()
        #expect(configuration.setShortcut(controlOptionReturn, for: .maximize) == nil)
        #expect(configuration.shortcut(for: .maximize) == controlOptionReturn)
    }

    @Test func resetRestoresDefaults() {
        var configuration = ShortcutConfiguration()
        configuration.setShortcut(nil, for: .maximize)
        configuration.setShortcut(commandOptionF, for: .toggleFullScreen)
        configuration.resetToDefaults()
        #expect(configuration == ShortcutConfiguration())
        #expect(configuration.isDefault)
    }

    @Test func survivesEncodingIncludingClearedShortcuts() throws {
        var configuration = ShortcutConfiguration()
        configuration.setShortcut(nil, for: .maximize)
        configuration.setShortcut(commandOptionF, for: .toggleFullScreen)

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(ShortcutConfiguration.self, from: data)
        #expect(decoded == configuration)
        #expect(decoded.shortcut(for: .maximize) == nil)
        #expect(decoded.shortcut(for: .toggleFullScreen) == commandOptionF)
        #expect(decoded.shortcut(for: .leftHalf) == controlOptionLeft)
    }

    @Test func ignoresActionsItDoesNotKnow() throws {
        let json = #"{"someFutureAction":{"combo":{"keyCode":0,"modifiers":8}},"toggleFullScreen":{"combo":{"keyCode":3,"modifiers":10}}}"#
        let decoded = try JSONDecoder().decode(ShortcutConfiguration.self, from: Data(json.utf8))
        #expect(decoded.shortcut(for: .toggleFullScreen) == commandOptionF)
        #expect(decoded.assignments.count == 6)
    }

    /// Only the user's own changes are stored, so settings saved before the defaults
    /// changed do not carry the old defaults along.
    @Test func settingsSavedUnderTheOldDefaultsGetTheNewDefaults() throws {
        let nothingChanged = try JSONDecoder().decode(ShortcutConfiguration.self, from: Data("{}".utf8))
        #expect(nothingChanged.isDefault)
        #expect(nothingChanged.shortcut(for: .maximize) == controlOptionReturn)

        // Saved by a build whose defaults were ⌘↩, ⇧⌘←, ⇧⌘→: the user had removed
        // Right Half's shortcut and touched nothing else.
        let json = #"{"rightHalf":{}}"#
        let decoded = try JSONDecoder().decode(ShortcutConfiguration.self, from: Data(json.utf8))
        #expect(decoded.shortcut(for: .rightHalf) == nil)
        #expect(decoded.shortcut(for: .maximize) == controlOptionReturn)
        #expect(decoded.shortcut(for: .leftHalf) == controlOptionLeft)
        #expect(decoded.action(for: commandReturn) == nil)
        #expect(decoded.action(for: commandShiftLeft) == nil)
    }

    @Test func aShortcutTheUserGaveToAnotherActionIsNotAlsoADefault() throws {
        // The user had put ⌃⌥↑ on Top Left before Top Half got it as a default.
        let json = #"{"topLeft":{"combo":{"keyCode":126,"modifiers":3}}}"#
        let decoded = try JSONDecoder().decode(ShortcutConfiguration.self, from: Data(json.utf8))
        #expect(decoded.shortcut(for: .topLeft) == controlOptionUp)
        #expect(decoded.shortcut(for: .topHalf) == nil)
        #expect(decoded.action(for: controlOptionUp) == .topLeft)

        let combos = decoded.assignments.map(\.combo)
        #expect(Set(combos).count == combos.count)
    }
}

@Suite struct ShortcutStoreTests {
    @Test func loadsDefaultsWhenNothingIsSaved() {
        #expect(ShortcutStore(storage: InMemoryShortcutStorage()).load() == ShortcutConfiguration())
    }

    @Test func savedShortcutsComeBack() {
        let storage = InMemoryShortcutStorage()

        var configuration = ShortcutConfiguration()
        configuration.setShortcut(commandOptionF, for: .toggleFullScreen)
        configuration.setShortcut(nil, for: .rightHalf)
        ShortcutStore(storage: storage).save(configuration)

        let loaded = ShortcutStore(storage: storage).load()
        #expect(loaded == configuration)
        #expect(loaded.shortcut(for: .toggleFullScreen) == commandOptionF)
        #expect(loaded.shortcut(for: .rightHalf) == nil)
    }

    @Test func unreadableDataFallsBackToDefaults() {
        let storage = InMemoryShortcutStorage()
        storage.setData(Data("not json".utf8), forKey: "shortcuts")
        #expect(ShortcutStore(storage: storage).load() == ShortcutConfiguration())
    }
}

@Suite struct KeyComboTests {
    @Test func modifierSymbolsUseMenuOrder() {
        let all: KeyCombo.Modifiers = [.command, .shift, .option, .control]
        #expect(all.symbols == "⌃⌥⇧⌘")
        #expect(KeyCombo.Modifiers([.command, .shift]).symbols == "⇧⌘")
        #expect(controlOption.symbols == "⌃⌥")
        #expect(KeyCombo.Modifiers().symbols == "")
    }

    @Test func globalShortcutsNeedARealModifier() {
        #expect(controlOptionReturn.isValidGlobalShortcut)
        #expect(commandReturn.isValidGlobalShortcut)
        #expect(!KeyCombo(keyCode: KeyCode.returnKey, modifiers: []).isValidGlobalShortcut)
        #expect(!KeyCombo(keyCode: KeyCode.leftArrow, modifiers: [.shift]).isValidGlobalShortcut)
        // F5 on its own is fine: it types nothing.
        #expect(KeyCombo(keyCode: 96, modifiers: []).isValidGlobalShortcut)
    }

    @Test func specialKeyNames() {
        #expect(KeyCode.specialKeyName(for: KeyCode.returnKey) == "↩")
        #expect(KeyCode.specialKeyName(for: KeyCode.leftArrow) == "←")
        #expect(KeyCode.specialKeyName(for: KeyCode.rightArrow) == "→")
        #expect(KeyCode.specialKeyName(for: KeyCode.upArrow) == "↑")
        #expect(KeyCode.specialKeyName(for: KeyCode.downArrow) == "↓")
        #expect(KeyCode.specialKeyName(for: 122) == "F1")
        #expect(KeyCode.specialKeyName(for: 90) == "F20")
        #expect(KeyCode.specialKeyName(for: 0) == nil)
    }
}
