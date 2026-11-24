import AppKit
import ApplicationServices
import CutterCore

enum WindowManagerError: Error, CustomStringConvertible {
    case accessibilityNotGranted
    case noFocusedWindow
    case windowIsFullScreen
    case noScreen
    case notSupported
    case failed(AXError)

    var description: String {
        switch self {
        case .accessibilityNotGranted: return "Accessibility access is not granted"
        case .noFocusedWindow: return "the frontmost app has no focused window"
        case .windowIsFullScreen: return "the window is in native full screen"
        case .noScreen: return "no screen found for the window"
        case .notSupported: return "the window does not support this"
        case .failed(let error): return "Accessibility error \(error.rawValue)"
        }
    }
}

/// Moves and resizes other apps' windows through the Accessibility API.
struct WindowManager {
    func perform(_ action: WindowAction) throws {
        guard AXIsProcessTrusted() else {
            throw WindowManagerError.accessibilityNotGranted
        }
        try perform(action, on: focusedWindow())
    }

    func perform(_ action: WindowAction, on window: AXUIElement) throws {
        switch action.behavior {
        case .place(let unit):
            try place(window, in: unit)
        case .toggleFullScreen:
            try toggleFullScreen(window)
        }
    }

    /// A window of the given process, found by its title.
    func window(titled title: String, inProcess pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else {
            return nil
        }
        return windows.first { window in
            var windowTitle: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &windowTitle)
            return windowTitle as? String == title
        }
    }

    // MARK: - Actions

    private func place(_ window: AXUIElement, in unit: UnitRect) throws {
        if bool(window, Attribute.fullScreen) == true {
            throw WindowManagerError.windowIsFullScreen
        }
        let current = try frame(of: window)
        guard let visibleFrame = Self.currentScreenLayout().visibleFrame(forWindowFrame: current) else {
            throw WindowManagerError.noScreen
        }
        let target = PlacementGeometry.frame(for: unit, in: visibleFrame)

        try withEnhancedUserInterfaceDisabled(for: window) {
            // Size first so the window fits on a smaller screen before it moves, then
            // size again because macOS can clamp the first resize to the old position.
            let firstResize = set(window, kAXSizeAttribute, size: target.size)
            let move = set(window, kAXPositionAttribute, point: target.origin)
            let secondResize = set(window, kAXSizeAttribute, size: target.size)

            if move != .success, firstResize != .success, secondResize != .success {
                throw Self.error(for: move)
            }

            guard let actual = try? frame(of: window), actual.size != target.size else {
                return
            }
            let origin = PlacementGeometry.settledOrigin(
                for: unit,
                target: target,
                actualSize: actual.size,
                visibleFrame: visibleFrame
            )
            if origin != actual.origin {
                _ = set(window, kAXPositionAttribute, point: origin)
            }
        }
    }

    private func toggleFullScreen(_ window: AXUIElement) throws {
        guard let isFullScreen = bool(window, Attribute.fullScreen) else {
            throw WindowManagerError.notSupported
        }
        let newValue: CFBoolean = isFullScreen ? kCFBooleanFalse : kCFBooleanTrue
        let result = AXUIElementSetAttributeValue(window, Attribute.fullScreen as CFString, newValue)
        guard result == .success else {
            throw Self.error(for: result)
        }
    }

    // MARK: - Finding the window

    private func focusedWindow() throws -> AXUIElement {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowManagerError.noFocusedWindow
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // The shortcut handler runs on the main thread; do not hang on an unresponsive app.
        AXUIElementSetMessagingTimeout(appElement, 1)

        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value)
            if result == .apiDisabled {
                throw WindowManagerError.accessibilityNotGranted
            }
            if result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                return value as! AXUIElement
            }
        }
        throw WindowManagerError.noFocusedWindow
    }

    private static func currentScreenLayout() -> ScreenLayout {
        ScreenLayout(cocoaScreens: NSScreen.screens.map { ($0.frame, $0.visibleFrame) })
    }

    // MARK: - Accessibility plumbing

    private enum Attribute {
        static let fullScreen = "AXFullScreen"
        static let enhancedUserInterface = "AXEnhancedUserInterface"
    }

    private static func error(for result: AXError) -> WindowManagerError {
        result == .apiDisabled ? .accessibilityNotGranted : .failed(result)
    }

    /// Apps with "enhanced user interface" on (set by assistive tools, and by some apps on
    /// themselves) animate Accessibility moves, which makes a resize land in the wrong
    /// place. Turn it off for the move and put it back afterwards.
    private func withEnhancedUserInterfaceDisabled(for window: AXUIElement, _ body: () throws -> Void) rethrows {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else {
            try body()
            return
        }
        let app = AXUIElementCreateApplication(pid)
        let wasEnabled = bool(app, Attribute.enhancedUserInterface) == true
        if wasEnabled {
            AXUIElementSetAttributeValue(app, Attribute.enhancedUserInterface as CFString, kCFBooleanFalse)
        }
        defer {
            if wasEnabled {
                AXUIElementSetAttributeValue(app, Attribute.enhancedUserInterface as CFString, kCFBooleanTrue)
            }
        }
        try body()
    }

    /// The window's frame in Accessibility coordinates (origin top-left).
    func frame(of window: AXUIElement) throws -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = try value(window, kAXPositionAttribute),
              AXValueGetValue(position, .cgPoint, &origin),
              let dimensions = try value(window, kAXSizeAttribute),
              AXValueGetValue(dimensions, .cgSize, &size)
        else {
            throw WindowManagerError.notSupported
        }
        return CGRect(origin: origin, size: size)
    }

    private func value(_ element: AXUIElement, _ attribute: String) throws -> AXValue? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            throw Self.error(for: result)
        }
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return (value as! AXValue)
    }

    private func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private func set(_ element: AXUIElement, _ attribute: String, point: CGPoint) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else {
            return .failure
        }
        return AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    private func set(_ element: AXUIElement, _ attribute: String, size: CGSize) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else {
            return .failure
        }
        return AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }
}
