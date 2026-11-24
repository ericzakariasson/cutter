import Testing

@testable import CutterCore

private func meaning(_ modifiers: KeyCombo.Modifiers, character: String) -> String? {
    // The key code is irrelevant for keys that type a character.
    WellKnownShortcut.usualMeaning(of: KeyCombo(keyCode: 0, modifiers: modifiers), character: character)
}

private func meaning(_ modifiers: KeyCombo.Modifiers, key: UInt16) -> String? {
    WellKnownShortcut.usualMeaning(of: KeyCombo(keyCode: key, modifiers: modifiers), character: nil)
}

@Suite struct WellKnownShortcutTests {
    @Test func theShortcutsTheReviewNamed() {
        #expect(meaning([.command], character: "q") == "quits the app")
        #expect(meaning([.command], character: "c") == "copies")
        #expect(meaning([.command], character: "v") == "pastes")
        #expect(meaning([.command], character: "w") == "closes the window")
        #expect(meaning([.command], key: KeyCode.tab) == "switches apps")
    }

    @Test func editingAndSystemShortcuts() {
        #expect(meaning([.command], character: "x") != nil)
        #expect(meaning([.command], character: "z") != nil)
        #expect(meaning([.command, .shift], character: "z") != nil)
        #expect(meaning([.command], character: "a") != nil)
        #expect(meaning([.command], character: "s") != nil)
        #expect(meaning([.command], character: ",") != nil)
        #expect(meaning([.command], key: KeyCode.space) != nil)
        #expect(meaning([.command, .option], key: KeyCode.escape) != nil)
        #expect(meaning([.command, .control], character: "q") == "locks the screen")
        #expect(meaning([.command, .shift], character: "4") != nil)
        #expect(meaning([.command, .shift], character: "/") == "opens the Help menu")
    }

    @Test func textNavigation() {
        #expect(meaning([.command], key: KeyCode.returnKey) == "sends or submits in many apps")
        #expect(meaning([.command], key: KeyCode.leftArrow) != nil)
        #expect(meaning([.command, .shift], key: KeyCode.rightArrow) != nil)
        #expect(meaning([.option], key: KeyCode.leftArrow) != nil)
        #expect(meaning([.option, .shift], key: KeyCode.rightArrow) != nil)
        #expect(meaning([.command], key: KeyCode.upArrow) != nil)
        #expect(meaning([.option], key: KeyCode.delete) != nil)
        #expect(meaning([.control], key: KeyCode.leftArrow) == "switches Spaces")
    }

    @Test func lettersIgnoreCase() {
        #expect(meaning([.command], character: "Q") == "quits the app")
    }

    @Test func theModifiersMustMatchExactly() {
        #expect(meaning([.command, .option], character: "q") == nil)
        #expect(meaning([.control], character: "c") == nil)
        #expect(meaning([.command, .control, .option], key: KeyCode.tab) == nil)
    }

    @Test func ordinaryShortcutsHaveNoMeaning() {
        #expect(meaning([.control, .option], character: "t") == nil)
        #expect(meaning([.control, .option, .command], key: KeyCode.leftArrow) == nil)
        #expect(meaning([.command], character: "j") == nil)
    }

    @Test func cuttersDefaultsAreNotWellKnownShortcuts() {
        for (_, combo) in ShortcutConfiguration.defaultShortcuts {
            #expect(WellKnownShortcut.usualMeaning(of: combo, character: nil) == nil)
        }
    }

    @Test func aSpecialKeyIsMatchedByPositionWhateverItTypes() {
        let commandSpace = KeyCombo(keyCode: KeyCode.space, modifiers: [.command])
        #expect(WellKnownShortcut.usualMeaning(of: commandSpace, character: " ") == "opens Spotlight")
    }
}
