import AppKit
import ApplicationServices
import CutterCore

enum WindowManagerError: Error, CustomStringConvertible {
    case accessibilityNotGranted
    case noFocusedWindow
    case windowIsFullScreen
    case appNotResponding
    case noScreen
    case notSupported
    case failed(AXError)

    var description: String {
        switch self {
        case .accessibilityNotGranted: return "Accessibility access is not granted"
        case .noFocusedWindow: return "the frontmost app has no focused window"
        case .windowIsFullScreen: return "the window is in native full screen"
        case .appNotResponding: return "the app did not answer in time"
        case .noScreen: return "no screen found for the window"
        case .notSupported: return "the window does not support this"
        case .failed(let error): return "Accessibility error \(error.rawValue)"
        }
    }
}

/// Moves and resizes other apps' windows through the Accessibility API.
final class WindowManager {
    /// How long one Accessibility call may wait for an app to answer, in seconds.
    static let messagingTimeout: Float = 1

    /// The last window Cutter placed, the frame it ended up with, and the part of the
    /// visible area it was meant to cover. A screen does not always let a window take the
    /// whole frame it is given. Remembering the intent lets a window that is sent on to
    /// another display, or back, cover the right part there instead of an approximation
    /// measured from where it landed.
    private var lastPlacement: (window: AXUIElement, frame: CGRect, unit: UnitRect)?

    init() {
        // Shortcuts run on the main thread, so an app that has stopped responding must not
        // hold Cutter up. The timeout is set for the whole process: one set on an app's
        // element does not carry over to the window elements read from it.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)
    }

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
        case .moveToDisplay(let direction):
            try move(window, toDisplay: direction)
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
        // Read the frame first: it is the call that reports an app that is not answering,
        // so nothing else waits on that app.
        let current = try frame(of: window)
        if bool(window, Attribute.fullScreen) == true {
            throw WindowManagerError.windowIsFullScreen
        }
        guard let visibleFrame = Self.currentScreenLayout().visibleFrame(forWindowFrame: current) else {
            throw WindowManagerError.noScreen
        }
        let target = PlacementGeometry.frame(for: unit, in: visibleFrame)
        try setFrame(of: window, to: target, covering: unit, of: visibleFrame, crossingDisplays: false)
    }

    /// Moves the window to the previous or next display. Does nothing with one display.
    private func move(_ window: AXUIElement, toDisplay direction: DisplayDirection) throws {
        let current = try frame(of: window)
        if bool(window, Attribute.fullScreen) == true {
            throw WindowManagerError.windowIsFullScreen
        }
        // Still where Cutter last put it: go by what it was meant to cover.
        var knownUnit: UnitRect?
        if let last = lastPlacement, CFEqual(last.window, window), last.frame == current {
            knownUnit = last.unit
        }
        guard let move = Self.currentScreenLayout().move(windowFrame: current, to: direction, covering: knownUnit) else {
            return
        }
        try setFrame(of: window, to: move.frame, covering: move.unit, of: move.visibleFrame, crossingDisplays: true)
    }

    /// Gives the window a frame, and keeps it on screen if it refuses the size.
    /// `unit` is the part of `visibleFrame` that `target` covers.
    private func setFrame(
        of window: AXUIElement,
        to target: CGRect,
        covering unit: UnitRect,
        of visibleFrame: CGRect,
        crossingDisplays: Bool
    ) throws {
        try withEnhancedUserInterfaceDisabled(for: window) {
            // Size first so the window fits on a smaller screen before it moves, then
            // size again because macOS can clamp the first resize to the old position.
            let firstResize = set(window, kAXSizeAttribute, size: target.size)
            let move = set(window, kAXPositionAttribute, point: target.origin)
            let secondResize = set(window, kAXSizeAttribute, size: target.size)

            if move != .success, firstResize != .success, secondResize != .success {
                throw Self.error(for: move)
            }

            var actual = try? frame(of: window)
            if crossingDisplays {
                // An app learns a moment after the move that its window is on another
                // screen, and until then limits the window to the old screen's size.
                // Ask again a few times. A window with a size limit of its own costs
                // the full wait, which is short.
                var attempts = 0
                while let frame = actual, frame.size != target.size, attempts < Self.resizeAttemptsAfterMove {
                    Thread.sleep(forTimeInterval: Self.pauseBetweenResizeAttempts)
                    _ = set(window, kAXSizeAttribute, size: target.size)
                    actual = try? self.frame(of: window)
                    attempts += 1
                }
            }

            if let frame = actual {
                let origin = frame.size == target.size
                    ? target.origin
                    : PlacementGeometry.settledOrigin(
                        for: unit,
                        target: target,
                        actualSize: frame.size,
                        visibleFrame: visibleFrame
                    )
                if origin != frame.origin {
                    _ = set(window, kAXPositionAttribute, point: origin)
                    actual = try? self.frame(of: window)
                }
            }
            lastPlacement = actual.map { (window, $0, unit) }
        }
    }

    private static let resizeAttemptsAfterMove = 3
    private static let pauseBetweenResizeAttempts: TimeInterval = 0.05

    private func toggleFullScreen(_ window: AXUIElement) throws {
        var value: CFTypeRef?
        let read = AXUIElementCopyAttributeValue(window, Attribute.fullScreen as CFString, &value)
        guard read == .success, let isFullScreen = value as? Bool else {
            throw read == .success || read == .noValue || read == .attributeUnsupported
                ? WindowManagerError.notSupported
                : Self.error(for: read)
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
        return try focusedWindow(ofProcess: app.processIdentifier)
    }

    func focusedWindow(ofProcess pid: pid_t) throws -> AXUIElement {
        let appElement = AXUIElementCreateApplication(pid)

        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value)
            // Do not ask an app that is not answering a second time.
            if result == .apiDisabled || result == .cannotComplete {
                throw Self.error(for: result)
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
        switch result {
        case .apiDisabled: return .accessibilityNotGranted
        case .cannotComplete: return .appNotResponding
        default: return .failed(result)
        }
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
