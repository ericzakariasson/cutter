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
    @Test func defaultsAreControlOptionReturnArrowsAndS() {
        let configuration = ShortcutConfiguration()
        #expect(configuration.shortcut(for: .maximize) == controlOptionReturn)
        #expect(configuration.shortcut(for: .leftHalf) == controlOptionLeft)
        #expect(configuration.shortcut(for: .rightHalf) == controlOptionRight)
        #expect(configuration.shortcut(for: .previousDisplay) == controlOptionUp)
        #expect(configuration.shortcut(for: .nextDisplay) == controlOptionDown)
        #expect(configuration.shortcut(for: .recentScreenshots) == KeyCombo(keyCode: KeyCode.s, modifiers: controlOption))

        #expect(configuration.shortcut(for: .emojiAndSymbols) == KeyCombo(keyCode: KeyCode.e, modifiers: [.control, .shift]))

        let assigned = configuration.assignments.map(\.action)
        #expect(assigned == [.maximize, .leftHalf, .rightHalf, .previousDisplay, .nextDisplay, .recentScreenshots, .emojiAndSymbols])
        #expect(configuration.isDefault)
    }

    /// The emoji picker is on the keys it was asked for; everything else is on Control-Option.
    @Test func everyDefaultUsesControlOptionExceptTheEmojiPicker() {
        for (action, combo) in ShortcutConfiguration.defaultShortcuts {
            #expect(combo.modifiers == (action == .emojiAndSymbols ? [.control, .shift] : controlOption))
        }
    }

    /// The emoji shortcut arrives as a default in a later version too. Someone who has
    /// already put ⌃⇧E on another action keeps it there.
    @Test func aSavedControlShiftEKeepsItsActionWhenTheEmojiDefaultArrives() throws {
        let json = #"{"topRight":{"combo":{"keyCode":14,"modifiers":5}}}"#
        let decoded = try JSONDecoder().decode(ShortcutConfiguration.self, from: Data(json.utf8))
        #expect(decoded.shortcut(for: .topRight) == KeyCombo(keyCode: KeyCode.e, modifiers: [.control, .shift]))
        #expect(decoded.shortcut(for: .emojiAndSymbols) == nil)
        // Another choice of his own for the picker is kept as well.
        var configuration = decoded
        configuration.setShortcut(KeyCombo(keyCode: KeyCode.e, modifiers: [.control, .option]), for: .emojiAndSymbols)
        #expect(configuration.shortcut(for: .emojiAndSymbols) == KeyCombo(keyCode: KeyCode.e, modifiers: [.control, .option]))
        #expect(configuration.shortcut(for: .topRight) == KeyCombo(keyCode: KeyCode.e, modifiers: [.control, .shift]))
    }

    @Test func theEmojiPickerIsCalledWhatMacOSCallsIt() {
        #expect(WindowAction.emojiAndSymbols.title == "Show Emoji & Symbols")
        #expect(WindowAction.emojiAndSymbols.rawValue == "emojiAndSymbols")
        #expect(WindowAction.allCases.last == .emojiAndSymbols)
        #expect(!WindowAction.emojiAndSymbols.movesBetweenDisplays)
    }

    /// The screenshots shortcut arrived as a default in a later version. Someone who had
    /// already put ⌃⌥S on another action keeps it there.
    @Test func aSavedControlOptionSKeepsItsActionWhenTheScreenshotsDefaultArrives() throws {
        let json = #"{"topLeft":{"combo":{"keyCode":1,"modifiers":3}}}"#
        let decoded = try JSONDecoder().decode(ShortcutConfiguration.self, from: Data(json.utf8))
        #expect(decoded.shortcut(for: .topLeft) == KeyCombo(keyCode: KeyCode.s, modifiers: controlOption))
        #expect(decoded.shortcut(for: .recentScreenshots) == nil)
    }

    /// The screenshots panel moves no window. The emoji picker has a way that needs no
    /// access, so its shortcut stays live without it too.
    @Test func onlyWhatMovesAWindowNeedsAccessibilityAccess() {
        for action in WindowAction.allCases {
            #expect(action.needsAccessibility == (action != .recentScreenshots && action != .emojiAndSymbols))
        }
    }

    @Test func topAndBottomHalfCornersAndFullScreenHaveNoDefault() {
        let configuration = ShortcutConfiguration()
        let unassigned: [WindowAction] = [.topHalf, .bottomHalf, .topLeft, .topRight, .bottomLeft, .bottomRight, .toggleFullScreen]
        for action in unassigned {
            #expect(configuration.shortcut(for: action) == nil)
        }
    }

    @Test func noTwoDefaultsShareAShortcut() {
        let combos = Array(ShortcutConfiguration.defaultShortcuts.values)
        #expect(Set(combos).count == combos.count)
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
        #expect(decoded.assignments.count == ShortcutConfiguration.defaultShortcuts.count + 1)
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
        // The user had put ⌃⌥↑ on Top Left before "previous display" got it as a default.
        let json = #"{"topLeft":{"combo":{"keyCode":126,"modifiers":3}}}"#
        let decoded = try JSONDecoder().decode(ShortcutConfiguration.self, from: Data(json.utf8))
        #expect(decoded.shortcut(for: .topLeft) == controlOptionUp)
        #expect(decoded.shortcut(for: .previousDisplay) == nil)
        #expect(decoded.action(for: controlOptionUp) == .topLeft)
        #expect(decoded.shortcut(for: .nextDisplay) == controlOptionDown)

        let combos = decoded.assignments.map(\.combo)
        #expect(Set(combos).count == combos.count)
    }

    /// ⌃⌥↑ and ⌃⌥↓ were the defaults of Top Half and Bottom Half before they became the
    /// defaults for moving between displays.
    @Test func halvesTheUserSavedKeepTheirArrowsAndTheDisplayMovesStayUnassigned() throws {
        // The user had recorded both arrows for the halves themselves.
        let json = #"{"topHalf":{"combo":{"keyCode":126,"modifiers":3}},"bottomHalf":{"combo":{"keyCode":125,"modifiers":3}}}"#
        let decoded = try JSONDecoder().decode(ShortcutConfiguration.self, from: Data(json.utf8))
        #expect(decoded.shortcut(for: .topHalf) == controlOptionUp)
        #expect(decoded.shortcut(for: .bottomHalf) == controlOptionDown)
        #expect(decoded.shortcut(for: .previousDisplay) == nil)
        #expect(decoded.shortcut(for: .nextDisplay) == nil)

        let combos = decoded.assignments.map(\.combo)
        #expect(Set(combos).count == combos.count)
    }

    @Test func halvesLeftOnTheirOldDefaultsGiveTheArrowsToTheDisplayMoves() throws {
        // Nothing saved for the halves: they had the arrows only as defaults.
        let json = #"{"maximize":{"combo":{"keyCode":3,"modifiers":10}}}"#
        let decoded = try JSONDecoder().decode(ShortcutConfiguration.self, from: Data(json.utf8))
        #expect(decoded.shortcut(for: .maximize) == commandOptionF)
        #expect(decoded.shortcut(for: .topHalf) == nil)
        #expect(decoded.shortcut(for: .bottomHalf) == nil)
        #expect(decoded.shortcut(for: .previousDisplay) == controlOptionUp)
        #expect(decoded.shortcut(for: .nextDisplay) == controlOptionDown)
    }

    @Test func aHalfTheUserClearedStaysCleared() throws {
        let json = #"{"topHalf":{}}"#
        let decoded = try JSONDecoder().decode(ShortcutConfiguration.self, from: Data(json.utf8))
        #expect(decoded.shortcut(for: .topHalf) == nil)
        #expect(decoded.shortcut(for: .previousDisplay) == controlOptionUp)
    }

    @Test func recordingADefaultForAnotherActionMovesIt() {
        var configuration = ShortcutConfiguration()
        let displaced = configuration.setShortcut(controlOptionUp, for: .topHalf)
        #expect(displaced == .previousDisplay)
        #expect(configuration.shortcut(for: .topHalf) == controlOptionUp)
        #expect(configuration.shortcut(for: .previousDisplay) == nil)

        let combos = configuration.assignments.map(\.combo)
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
