import AppKit
import Carbon.HIToolbox
import CutterCore

extension KeyCombo.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var result: KeyCombo.Modifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }

    var eventFlags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if contains(.control) { result.insert(.control) }
        if contains(.option) { result.insert(.option) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.command) { result.insert(.command) }
        return result
    }

    /// The modifier mask `RegisterEventHotKey` expects.
    var carbonFlags: UInt32 {
        var result = 0
        if contains(.control) { result |= controlKey }
        if contains(.option) { result |= optionKey }
        if contains(.shift) { result |= shiftKey }
        if contains(.command) { result |= cmdKey }
        return UInt32(result)
    }
}

enum KeyComboFormatter {
    /// For example "⇧⌘←".
    static func string(for combo: KeyCombo) -> String {
        combo.modifiers.symbols + keyName(for: combo.keyCode)
    }

    static func keyName(for keyCode: UInt16) -> String {
        if let special = KeyCode.specialKeyName(for: keyCode) {
            return special
        }
        if let character = layoutCharacter(for: keyCode) {
            // The keypad's 1 and the main 1 are different shortcuts; tell them apart.
            return KeyCode.keypadCharacterKeys.contains(keyCode) ? "Keypad \(character)" : character.uppercased()
        }
        return "Key \(keyCode)"
    }

    /// The key equivalent that makes an `NSMenuItem` display this key and answer to it
    /// while the menu is open, if the key has one. Keypad Clear and Help have none.
    ///
    /// These are the characters AppKit documents for menu items, which are not always
    /// the ones a key event carries: Delete is 0x08 here and 0x7F in the event, Forward
    /// Delete is 0x7F here and a function-key character in the event.
    ///
    /// A key equivalent names a character, not a key. The keypad's 1 gets "1", so the
    /// item also answers to the main 1; `StatusMenuController` checks which key it was.
    static func menuKeyEquivalent(for keyCode: UInt16) -> String? {
        let functionKey: Int?
        switch keyCode {
        case KeyCode.returnKey: return "\r"
        case KeyCode.keypadEnter: return "\u{3}"
        case KeyCode.tab: return "\t"
        case KeyCode.space: return " "
        case KeyCode.delete: return "\u{8}"
        case KeyCode.forwardDelete: return "\u{7F}"
        case KeyCode.escape: return "\u{1B}"
        case KeyCode.leftArrow: functionKey = NSLeftArrowFunctionKey
        case KeyCode.rightArrow: functionKey = NSRightArrowFunctionKey
        case KeyCode.upArrow: functionKey = NSUpArrowFunctionKey
        case KeyCode.downArrow: functionKey = NSDownArrowFunctionKey
        case KeyCode.home: functionKey = NSHomeFunctionKey
        case KeyCode.end: functionKey = NSEndFunctionKey
        case KeyCode.pageUp: functionKey = NSPageUpFunctionKey
        case KeyCode.pageDown: functionKey = NSPageDownFunctionKey
        case KeyCode.keypadClear, KeyCode.help: return nil
        default:
            if let index = KeyCode.functionKeyCodes.firstIndex(of: keyCode) {
                functionKey = NSF1FunctionKey + index
            } else {
                return layoutCharacter(for: keyCode)?.lowercased()
            }
        }
        return functionKey.flatMap(UnicodeScalar.init).map { String(Character($0)) }
    }

    /// What the key types on the current keyboard layout, without modifiers.
    static func layoutCharacter(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else {
            return nil
        }
        let string = String(utf16CodeUnits: characters, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return string.isEmpty ? nil : string
    }
}
