import AppKit
import ApplicationServices
import Carbon
import CutterCore

/// Opens the macOS emoji picker (Emoji & Symbols) in the app in front, so that what is
/// picked lands at that app's insertion point.
///
/// Three ways, tried in this order:
///
/// 1. **The app's own menu item.** Nearly every app has Emoji & Symbols in its Edit
///    menu, and AppKit marks it with the name of what it does, `orderFrontCharacterPalette:`.
///    Cutter finds the item by that mark and presses it through Accessibility. This is
///    the app opening its own picker: it does not depend on which keys macOS has given
///    the picker (Control-Command-Space on some Macs, the Globe key and E on others), on
///    the language of the menus, or on the keys still held from Cutter's own shortcut.
/// 2. **The Character Viewer input source.** Some apps have no such menu item. macOS
///    also offers the picker in its Input menu, as an input source, for whichever app is
///    in front. Selecting that source needs neither the menu item nor Accessibility.
/// 3. **The keystroke.** Only if the input source cannot be selected: Control-Command-Space,
///    posted with nothing else held.
///
/// Whether a picker really came up cannot be known for sure from outside, so the log
/// says which way was taken and what the system reported, and nothing about what is
/// typed or shown.
final class EmojiPicker {
    enum Route: String, Equatable {
        case cutterItself = "Cutter itself"
        case menuItem = "menu item"
        case inputSource = "input source"
        case keystroke
    }

    enum MenuAnswer: Equatable {
        case pressed
        /// Pressed, but the app took too long to say so. It counts as pressed: asking
        /// another way on top could close the picker again.
        case pressedWithoutAnswer
        case notFound
        case disabled
        case failed(Int32)
    }

    /// Everything this does to the system, replaceable in tests.
    struct Environment {
        var frontApp: () -> (pid: pid_t, bundleID: String?)? = EmojiPicker.frontApp
        var ownPID: pid_t = ProcessInfo.processInfo.processIdentifier
        var isTrusted: () -> Bool = { AXIsProcessTrusted() }
        var showInCutter: () -> Void = { NSApp.orderFrontCharacterPalette(nil) }
        var pressMenuItem: (pid_t) -> MenuAnswer = EmojiPicker.pressMenuItem
        var selectInputSource: () -> Bool = EmojiPicker.selectInputSource
        var postKeystroke: () -> Bool = EmojiPicker.postKeystroke
        /// What can be seen of a picker afterwards, for the log.
        var whatIsUp: () -> String = EmojiPicker.whatIsUp
        var log: (String) -> Void = { NSLog("Cutter: emoji picker: %@", $0) }
        /// Asking another app through Accessibility waits for its answer, so it is kept
        /// off the main thread.
        var inBackground: (@escaping () -> Void) -> Void = { DispatchQueue.global(qos: .userInitiated).async(execute: $0) }
        var onMain: (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }
        var later: (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
        var now: () -> Date = { Date() }
    }

    /// The mark AppKit puts on the Emoji & Symbols menu item of every app.
    static let menuItemIdentifier = "orderFrontCharacterPalette:"
    static let inputSourceID = "com.apple.CharacterPaletteIM"
    /// A second request this soon after the first is the same key press.
    static let repeatInterval: TimeInterval = 0.4

    var environment: Environment
    /// Called with the way that was taken, or nil when none worked. For tests.
    var onResult: ((Route?) -> Void)?
    private var lastRequest: Date?

    init(environment: Environment = Environment()) {
        self.environment = environment
    }

    func show() {
        let now = environment.now()
        if let lastRequest, now.timeIntervalSince(lastRequest) < Self.repeatInterval {
            return
        }
        lastRequest = now

        guard let app = environment.frontApp() else {
            environment.log("no app in front")
            fallBack()
            return
        }
        if app.pid == environment.ownPID {
            environment.showInCutter()
            finish(.cutterItself, "opened in Cutter itself")
            return
        }
        // The bundle identifier says which app, and nothing about what is in it.
        let name = app.bundleID ?? "an app without an identifier"
        guard environment.isTrusted() else {
            environment.log("no Accessibility access, so the menu item of \(name) was not tried")
            fallBack()
            return
        }
        environment.inBackground { [environment] in
            let answer = environment.pressMenuItem(app.pid)
            environment.onMain { [weak self] in
                self?.menuAnswered(answer, in: name)
            }
        }
    }

    private func menuAnswered(_ answer: MenuAnswer, in name: String) {
        switch answer {
        case .pressed:
            finish(.menuItem, "pressed the Emoji & Symbols menu item of \(name)")
        case .pressedWithoutAnswer:
            finish(.menuItem, "pressed the Emoji & Symbols menu item of \(name); the app had not answered in time")
        case .notFound:
            environment.log("\(name) has no Emoji & Symbols menu item")
            fallBack()
        case .disabled:
            environment.log("the Emoji & Symbols menu item of \(name) is switched off")
            fallBack()
        case .failed(let code):
            environment.log("the menus of \(name) could not be read (Accessibility error \(code))")
            fallBack()
        }
    }

    private func fallBack() {
        if environment.selectInputSource() {
            finish(.inputSource, "selected the Character Viewer input source")
        } else if environment.isTrusted(), environment.postKeystroke() {
            finish(.keystroke, "the input source could not be selected; sent Control-Command-Space")
        } else {
            environment.log("the input source could not be selected and no keystroke could be sent; nothing opened")
            onResult?(nil)
        }
    }

    private func finish(_ route: Route, _ message: String) {
        environment.log(message)
        onResult?(route)
        // A look afterwards, for the log only: no way of asking is tried on top of it.
        environment.later(0.6) { [environment] in
            environment.log("0.6 s later: \(environment.whatIsUp())")
        }
    }
}

// MARK: - The real thing

extension EmojiPicker {
    static func frontApp() -> (pid: pid_t, bundleID: String?)? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return (app.processIdentifier, app.bundleIdentifier)
    }

    /// Finds the Emoji & Symbols item in the app's menu bar by its mark and presses it.
    /// Reads marks only, never a title.
    static func pressMenuItem(in pid: pid_t) -> MenuAnswer {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)

        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value)
        guard error == .success, let menuBar = value, CFGetTypeID(menuBar) == AXUIElementGetTypeID() else {
            return .failed(error.rawValue)
        }
        var menus = children(of: menuBar as! AXUIElement)
        // The Edit menu is nearly always the fourth: Apple, the app, File, Edit.
        if menus.count > 3 {
            menus.insert(menus.remove(at: 3), at: 0)
        }
        for menu in menus {
            for list in children(of: menu) {
                for item in children(of: list) where identifier(of: item) == menuItemIdentifier {
                    return press(item)
                }
            }
        }
        return .notFound
    }

    private static func press(_ item: AXUIElement) -> MenuAnswer {
        var enabled: AnyObject?
        if AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabled) == .success,
           (enabled as? NSNumber)?.boolValue == false {
            return .disabled
        }
        switch AXUIElementPerformAction(item, kAXPressAction as CFString) {
        case .success: return .pressed
        case .cannotComplete: return .pressedWithoutAnswer
        case let error: return .failed(error.rawValue)
        }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return (value as? [AXUIElement]) ?? []
    }

    private static func identifier(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func characterViewerSource() -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: inputSourceID] as CFDictionary
        // Only sources that are switched on: Cutter changes no input settings.
        let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]
        return sources?.first
    }

    private static func isSelected(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelected) else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    /// Asks macOS for the picker the way its Input menu does. Main thread only.
    static func selectInputSource() -> Bool {
        guard let source = characterViewerSource() else {
            return false
        }
        // A source still marked as selected would make selecting it a no-op, whether or
        // not its window is up. Selecting it afresh always ends with the picker shown.
        if isSelected(source) {
            TISDeselectInputSource(source)
        }
        return TISSelectInputSource(source) == noErr
    }

    /// Control-Command-Space with nothing else held: the keys of Cutter's own shortcut,
    /// still down at this moment, are not part of it.
    static func postKeystroke() -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else {
            return false
        }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(KeyCode.space), keyDown: isDown) else {
                return false
            }
            event.flags = [.maskControl, .maskCommand]
            event.post(tap: .cghidEventTap)
        }
        return true
    }

    /// Two signs of a picker, neither of them certain: a window of the Character Viewer
    /// on screen, and its input source marked as selected. Windows are told apart by
    /// the app they belong to; no title is read.
    static func whatIsUp() -> String {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let owners = Set(windows.compactMap { $0[kCGWindowOwnerPID as String] as? pid_t })
        let hasWindow = owners.contains { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier == inputSourceID }
        let selected = characterViewerSource().map(isSelected) ?? false
        return "a Character Viewer window is on screen: \(hasWindow ? "yes" : "no"); its input source is selected: \(selected ? "yes" : "no")"
    }
}
