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
            return character.uppercased()
        }
        return "Key \(keyCode)"
    }

    /// The key equivalent that makes an `NSMenuItem` display this key, if it has one.
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
