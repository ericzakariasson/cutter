import Foundation

/// Shortcuts that macOS or most apps already use. A global shortcut takes its keys away
/// from every app, so the recorder asks before accepting one of these.
public enum WellKnownShortcut {
    /// What the combination usually does, as the end of a sentence starting with the
    /// shortcut ("⌘Q usually quits the app"), or nil when it has no common meaning.
    ///
    /// - Parameter character: what the key types on the current keyboard layout, for keys
    ///   that type something. Letter shortcuts follow the layout, not the key's position.
    public static func usualMeaning(of combo: KeyCombo, character: String?) -> String? {
        if let meaning = specialKeys[Key(keyCode: combo.keyCode, modifiers: combo.modifiers)] {
            return meaning
        }
        // A space is typed by the space bar, which is matched as a special key above.
        guard let character = character?.lowercased(), character != " " else {
            return nil
        }
        return characters[combo.modifiers]?[character]
    }

    private struct Key: Hashable {
        let keyCode: UInt16
        let modifiers: KeyCombo.Modifiers
    }

    private static let characters: [KeyCombo.Modifiers: [String: String]] = [
        [.command]: [
            "q": "quits the app",
            "w": "closes the window",
            "c": "copies",
            "v": "pastes",
            "x": "cuts",
            "z": "undoes the last change",
            "a": "selects everything",
            "s": "saves",
            "n": "opens a new window or document",
            "o": "opens a file",
            "p": "prints",
            "f": "finds",
            "t": "opens a new tab",
            "h": "hides the app",
            "m": "minimizes the window",
            ",": "opens the app's settings",
            "`": "switches between an app's windows",
        ],
        [.command, .shift]: [
            "z": "redoes the last change",
            "q": "logs you out",
            "3": "takes a screenshot",
            "4": "takes a screenshot",
            "5": "takes a screenshot",
        ],
        [.command, .control]: [
            "q": "locks the screen",
            "f": "toggles full screen",
        ],
        [.command, .option]: [
            "d": "shows or hides the Dock",
        ],
    ]

    private static let specialKeys: [Key: String] = {
        var keys: [Key: String] = [
            Key(keyCode: KeyCode.tab, modifiers: [.command]): "switches apps",
            Key(keyCode: KeyCode.tab, modifiers: [.command, .shift]): "switches apps",
            Key(keyCode: KeyCode.space, modifiers: [.command]): "opens Spotlight",
            Key(keyCode: KeyCode.space, modifiers: [.command, .option]): "opens a Finder search",
            Key(keyCode: KeyCode.space, modifiers: [.control]): "switches input sources",
            Key(keyCode: KeyCode.escape, modifiers: [.command, .option]): "opens Force Quit",
            Key(keyCode: KeyCode.returnKey, modifiers: [.command]): "sends or submits in many apps",
            Key(keyCode: KeyCode.delete, modifiers: [.command]): "deletes to the start of the line",
            Key(keyCode: KeyCode.delete, modifiers: [.option]): "deletes the previous word",
            Key(keyCode: KeyCode.upArrow, modifiers: [.control]): "opens Mission Control",
            Key(keyCode: KeyCode.downArrow, modifiers: [.control]): "shows the app's windows",
        ]
        for arrow in [KeyCode.leftArrow, KeyCode.rightArrow] {
            keys[Key(keyCode: arrow, modifiers: [.command])] = "moves to the start or end of the line"
            keys[Key(keyCode: arrow, modifiers: [.command, .shift])] = "selects to the start or end of the line"
            keys[Key(keyCode: arrow, modifiers: [.option])] = "moves by a word"
            keys[Key(keyCode: arrow, modifiers: [.option, .shift])] = "selects by a word"
            keys[Key(keyCode: arrow, modifiers: [.control])] = "switches Spaces"
        }
        for arrow in [KeyCode.upArrow, KeyCode.downArrow] {
            keys[Key(keyCode: arrow, modifiers: [.command])] = "moves to the start or end of the document"
            keys[Key(keyCode: arrow, modifiers: [.command, .shift])] = "selects to the start or end of the document"
        }
        return keys
    }()
}
