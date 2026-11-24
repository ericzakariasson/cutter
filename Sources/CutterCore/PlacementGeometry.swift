import CoreGraphics
import Foundation

/// Frame math for placements.
///
/// All rectangles here use the Accessibility coordinate space unless a name says "cocoa":
/// origin at the top-left corner of the primary screen, y growing downwards.
public enum PlacementGeometry {
    /// The frame a placement occupies inside a screen's visible area.
    ///
    /// Edges are rounded to whole points one by one, so adjacent placements share an edge
    /// exactly: no gap and no overlap between a left half and a right half.
    public static func frame(for unit: UnitRect, in visibleFrame: CGRect) -> CGRect {
        let minX = (visibleFrame.minX + CGFloat(unit.x) * visibleFrame.width).rounded()
        let maxX = (visibleFrame.minX + CGFloat(unit.x + unit.width) * visibleFrame.width).rounded()
        let minY = (visibleFrame.minY + CGFloat(unit.y) * visibleFrame.height).rounded()
        let maxY = (visibleFrame.minY + CGFloat(unit.y + unit.height) * visibleFrame.height).rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Converts between Cocoa screen coordinates (origin bottom-left of the primary screen)
    /// and Accessibility coordinates (origin top-left). The conversion is its own inverse.
    public static func flipped(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// The screen a window is on: the one showing most of it, or the nearest one when the
    /// window is entirely off-screen. Returns nil only when there are no screens.
    public static func screenIndex(forWindowFrame windowFrame: CGRect, screenFrames: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screenFrames.enumerated() {
            let overlap = screen.intersection(windowFrame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > 0, area > (best?.area ?? 0) {
                best = (index, area)
            }
        }
        if let best {
            return best.index
        }

        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        var nearest: (index: Int, distance: CGFloat)?
        for (index, screen) in screenFrames.enumerated() {
            let dx = max(screen.minX - center.x, 0, center.x - screen.maxX)
            let dy = max(screen.minY - center.y, 0, center.y - screen.maxY)
            let distance = dx * dx + dy * dy
            if distance < (nearest?.distance ?? .infinity) {
                nearest = (index, distance)
            }
        }
        return nearest?.index
    }

    /// Where to put a window that refused the target size (minimum size, fixed size, or
    /// size increments as in terminals).
    ///
    /// The window stays against the screen edges its placement touches: a right half that
    /// ends up wider than half the screen keeps its right edge on the screen's right edge.
    /// Placements that span an axis, or touch neither edge, are centred in the target.
    /// The result never leaves the visible area while the window fits in it.
    public static func settledOrigin(
        for unit: UnitRect,
        target: CGRect,
        actualSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let x = settle(
            targetMin: target.minX,
            targetLength: target.width,
            actualLength: actualSize.width,
            visibleMin: visibleFrame.minX,
            visibleLength: visibleFrame.width,
            touchesMin: unit.x <= edgeTolerance,
            touchesMax: unit.x + unit.width >= 1 - edgeTolerance
        )
        let y = settle(
            targetMin: target.minY,
            targetLength: target.height,
            actualLength: actualSize.height,
            visibleMin: visibleFrame.minY,
            visibleLength: visibleFrame.height,
            touchesMin: unit.y <= edgeTolerance,
            touchesMax: unit.y + unit.height >= 1 - edgeTolerance
        )
        return CGPoint(x: x, y: y)
    }

    private static let edgeTolerance = 0.0001

    private static func settle(
        targetMin: CGFloat,
        targetLength: CGFloat,
        actualLength: CGFloat,
        visibleMin: CGFloat,
        visibleLength: CGFloat,
        touchesMin: Bool,
        touchesMax: Bool
    ) -> CGFloat {
        var origin: CGFloat
        switch (touchesMin, touchesMax) {
        case (true, false):
            origin = targetMin
        case (false, true):
            origin = targetMin + targetLength - actualLength
        case (true, true), (false, false):
            origin = targetMin + (targetLength - actualLength) / 2
        }
        // When the window is larger than the visible area, the leading edge wins.
        origin = min(origin, visibleMin + visibleLength - actualLength)
        origin = max(origin, visibleMin)
        // Rounding down keeps a window that came out one point short against the top and
        // left edges instead of opening a gap under the menu bar.
        return origin.rounded(.down)
    }
}

/// The connected screens, in Accessibility coordinates.
public struct ScreenLayout: Equatable, Sendable {
    public struct Screen: Equatable, Sendable {
        /// The whole screen.
        public var frame: CGRect
        /// The screen without the menu bar and the Dock.
        public var visibleFrame: CGRect

        public init(frame: CGRect, visibleFrame: CGRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    public var screens: [Screen]

    public init(screens: [Screen]) {
        self.screens = screens
    }

    /// Builds a layout from `NSScreen` values, which use Cocoa coordinates.
    /// The first screen must be the primary one, as in `NSScreen.screens`.
    public init(cocoaScreens: [(frame: CGRect, visibleFrame: CGRect)]) {
        guard let primaryHeight = cocoaScreens.first?.frame.height else {
            self.screens = []
            return
        }
        self.screens = cocoaScreens.map { screen in
            Screen(
                frame: PlacementGeometry.flipped(screen.frame, primaryScreenHeight: primaryHeight),
                visibleFrame: PlacementGeometry.flipped(screen.visibleFrame, primaryScreenHeight: primaryHeight)
            )
        }
    }

    /// The visible area of the screen a window is on.
    public func visibleFrame(forWindowFrame windowFrame: CGRect) -> CGRect? {
        let index = PlacementGeometry.screenIndex(
            forWindowFrame: windowFrame,
            screenFrames: screens.map(\.frame)
        )
        return index.map { screens[$0].visibleFrame }
    }
}
