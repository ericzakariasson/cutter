import Foundation

/// Everything Cutter does on a shortcut: the placements and moves of the focused window,
/// showing the recent screenshots, and opening the emoji picker.
///
/// To add a placement: add a case, give it a `title`, and return its `UnitRect` from `behavior`.
/// The settings window, the menu and the shortcut storage pick it up from `allCases`, in
/// this order. The raw value is the persistence key, so do not rename existing cases.
public enum WindowAction: String, CaseIterable, Codable, Sendable {
    case maximize
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case previousDisplay
    case nextDisplay
    case toggleFullScreen
    case recentScreenshots
    case emojiAndSymbols

    public enum Behavior: Equatable, Sendable {
        /// Move and resize the window to this part of its screen's visible area.
        case place(UnitRect)
        /// Move the window to another display, keeping its place within the visible area.
        case moveToDisplay(DisplayDirection)
        /// Enter or leave native macOS full screen.
        case toggleFullScreen
        /// Show the panel with the most recent screenshots.
        case showRecentScreenshots
        /// Open the macOS emoji picker (Emoji & Symbols) in the app in front.
        case showEmojiAndSymbols
    }

    public var title: String {
        switch self {
        case .maximize: return "Maximize"
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .previousDisplay: return "Move to Previous Display"
        case .nextDisplay: return "Move to Next Display"
        case .toggleFullScreen: return "Toggle Full Screen"
        case .recentScreenshots: return "Show Recent Screenshots"
        // The name macOS gives it in its Input menu; the Edit menu says "Emoji & Symbols".
        case .emojiAndSymbols: return "Show Emoji & Symbols"
        }
    }

    public var behavior: Behavior {
        switch self {
        case .maximize: return .place(UnitRect(x: 0, y: 0, width: 1, height: 1))
        case .leftHalf: return .place(UnitRect(x: 0, y: 0, width: 0.5, height: 1))
        case .rightHalf: return .place(UnitRect(x: 0.5, y: 0, width: 0.5, height: 1))
        case .topHalf: return .place(UnitRect(x: 0, y: 0, width: 1, height: 0.5))
        case .bottomHalf: return .place(UnitRect(x: 0, y: 0.5, width: 1, height: 0.5))
        case .topLeft: return .place(UnitRect(x: 0, y: 0, width: 0.5, height: 0.5))
        case .topRight: return .place(UnitRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        case .bottomLeft: return .place(UnitRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
        case .bottomRight: return .place(UnitRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        case .previousDisplay: return .moveToDisplay(.previous)
        case .nextDisplay: return .moveToDisplay(.next)
        case .toggleFullScreen: return .toggleFullScreen
        case .recentScreenshots: return .showRecentScreenshots
        case .emojiAndSymbols: return .showEmojiAndSymbols
        }
    }

    /// Whether the action controls another app's window, which takes Accessibility access.
    /// Showing the screenshots does not. Neither does the emoji picker: it has a way
    /// that works without, and uses the better one when access is there.
    public var needsAccessibility: Bool {
        switch behavior {
        case .showRecentScreenshots, .showEmojiAndSymbols:
            return false
        case .place, .moveToDisplay, .toggleFullScreen:
            return true
        }
    }

    /// Whether the action needs a second display to do anything.
    public var movesBetweenDisplays: Bool {
        if case .moveToDisplay = behavior {
            return true
        }
        return false
    }
}

/// Which way to step through the displays. See `ScreenLayout.displayOrder`.
public enum DisplayDirection: Equatable, Sendable {
    case previous
    case next
}

/// A rectangle in fractions of a screen's visible area. The origin is the top-left corner.
public struct UnitRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
