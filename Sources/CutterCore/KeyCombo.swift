import Foundation

/// A key plus modifiers. `keyCode` is a macOS virtual key code, which names a physical key
/// and so stays the same across keyboard layouts.
public struct KeyCombo: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// The modifiers in the order macOS menus show them.
        public var symbols: String {
            var result = ""
            if contains(.control) { result += "⌃" }
            if contains(.option) { result += "⌥" }
            if contains(.shift) { result += "⇧" }
            if contains(.command) { result += "⌘" }
            return result
        }
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A global shortcut takes its key away from every app, so a bare key or Shift plus a
    /// key would make that key untypeable. Function keys are the exception.
    public var isValidGlobalShortcut: Bool {
        if KeyCode.functionKeys.contains(keyCode) {
            return true
        }
        return !modifiers.isDisjoint(with: [.command, .control, .option])
    }
}

/// Virtual key codes Cutter refers to by name.
public enum KeyCode {
    public static let s: UInt16 = 1
    public static let e: UInt16 = 14
    public static let returnKey: UInt16 = 36
    public static let tab: UInt16 = 48
    public static let space: UInt16 = 49
    public static let delete: UInt16 = 51
    public static let escape: UInt16 = 53
    public static let keypadClear: UInt16 = 71
    public static let keypadEnter: UInt16 = 76
    public static let help: UInt16 = 114
    public static let home: UInt16 = 115
    public static let pageUp: UInt16 = 116
    public static let forwardDelete: UInt16 = 117
    public static let end: UInt16 = 119
    public static let pageDown: UInt16 = 121
    public static let leftArrow: UInt16 = 123
    public static let rightArrow: UInt16 = 124
    public static let downArrow: UInt16 = 125
    public static let upArrow: UInt16 = 126

    /// F1 to F20, in order.
    public static let functionKeyCodes: [UInt16] = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    public static let functionKeys = Set(functionKeyCodes)

    /// The numeric keypad's digits and operators: keys that type a character the main
    /// part of the keyboard also has. Clear and Enter are not among them.
    public static let keypadCharacterKeys: Set<UInt16> = [65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]

    /// A display name for keys that do not type a character. Nil for ordinary keys, whose
    /// label depends on the keyboard layout.
    public static func specialKeyName(for keyCode: UInt16) -> String? {
        switch keyCode {
        case returnKey: return "↩"
        case keypadEnter: return "⌅"
        case keypadClear: return "⌧"
        case help: return "Help"
        case tab: return "⇥"
        case space: return "Space"
        case delete: return "⌫"
        case forwardDelete: return "⌦"
        case escape: return "⎋"
        case home: return "↖"
        case end: return "↘"
        case pageUp: return "⇞"
        case pageDown: return "⇟"
        case leftArrow: return "←"
        case rightArrow: return "→"
        case downArrow: return "↓"
        case upArrow: return "↑"
        default:
            if let index = functionKeyCodes.firstIndex(of: keyCode) {
                return "F\(index + 1)"
            }
            return nil
        }
    }
}
