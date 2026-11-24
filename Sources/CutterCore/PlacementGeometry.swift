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

    /// The part of a visible area a window covers, in fractions of that area. This is what
    /// a window keeps when it moves to another display.
    ///
    /// Edges within a few points of the area's edges or centre lines count as being on
    /// them, so a maximized or half-screen window stays exactly that on the other display
    /// even though macOS placed it a point off. A window that hangs outside the area, or
    /// is larger than it, is pulled inside: the result always lies within the unit square.
    public static func unitRect(of windowFrame: CGRect, in visibleFrame: CGRect) -> UnitRect {
        let horizontal = unitSpan(
            from: windowFrame.minX,
            to: windowFrame.maxX,
            visibleMin: visibleFrame.minX,
            visibleLength: visibleFrame.width
        )
        let vertical = unitSpan(
            from: windowFrame.minY,
            to: windowFrame.maxY,
            visibleMin: visibleFrame.minY,
            visibleLength: visibleFrame.height
        )
        return UnitRect(x: horizontal.start, y: vertical.start, width: horizontal.length, height: vertical.length)
    }

    /// How close, in points, an edge must be to a screen edge or centre line to count as on it.
    static let snapDistance: CGFloat = 4

    private static func unitSpan(
        from start: CGFloat,
        to end: CGFloat,
        visibleMin: CGFloat,
        visibleLength: CGFloat
    ) -> (start: Double, length: Double) {
        guard visibleLength > 0 else {
            return (0, 1)
        }
        func exactFraction(_ edge: CGFloat) -> Double {
            Double((edge - visibleMin) / visibleLength)
        }
        func snappedFraction(_ edge: CGFloat) -> Double {
            for anchor in [0, 0.5, 1] where abs(edge - (visibleMin + CGFloat(anchor) * visibleLength)) <= snapDistance {
                return anchor
            }
            return exactFraction(edge)
        }

        var first = snappedFraction(start)
        var last = snappedFraction(end)
        if last <= first {
            // A sliver of a window whose two edges snapped to the same line.
            first = exactFraction(start)
            last = exactFraction(end)
        }
        let length = min(max(last - first, 0), 1)
        return (min(max(first, 0), 1 - length), length)
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

    /// The index of the screen a window is on.
    public func screenIndex(forWindowFrame windowFrame: CGRect) -> Int? {
        PlacementGeometry.screenIndex(forWindowFrame: windowFrame, screenFrames: screens.map(\.frame))
    }

    /// The visible area of the screen a window is on.
    public func visibleFrame(forWindowFrame windowFrame: CGRect) -> CGRect? {
        screenIndex(forWindowFrame: windowFrame).map { screens[$0].visibleFrame }
    }

    // MARK: - Moving between displays

    /// The screens in the order "previous display" and "next display" step through them,
    /// as indices into `screens`.
    ///
    /// The order follows the arrangement in System Settings: rows from top to bottom, and
    /// left to right within a row. With displays stacked, "previous" is the one above;
    /// with displays side by side, the one to the left. Two screens share a row when the
    /// vertical centre of one lies within the height of the other, so side-by-side
    /// displays of different sizes or alignment still count as one row. The order depends
    /// only on the arrangement, not on which screen is the primary one.
    public var displayOrder: [Int] {
        let byHeight = screens.indices.sorted { a, b in
            let first = screens[a].frame
            let second = screens[b].frame
            return (first.midY, first.minX, a) < (second.midY, second.minX, b)
        }

        var rows: [[Int]] = []
        for index in byHeight {
            let frame = screens[index].frame
            if let top = rows.last?.first.map({ screens[$0].frame }),
               (top.minY...top.maxY).contains(frame.midY) || (frame.minY...frame.maxY).contains(top.midY) {
                rows[rows.count - 1].append(index)
            } else {
                rows.append([index])
            }
        }
        return rows.flatMap { row in
            row.sorted { a, b in
                (screens[a].frame.minX, a) < (screens[b].frame.minX, b)
            }
        }
    }

    /// The screen one step from another in `displayOrder`, wrapping at the ends. Nil with
    /// fewer than two screens.
    public func screenIndex(_ direction: DisplayDirection, from index: Int) -> Int? {
        let order = displayOrder
        guard order.count > 1, let position = order.firstIndex(of: index) else {
            return nil
        }
        let step = direction == .next ? 1 : order.count - 1
        return order[(position + step) % order.count]
    }

    public struct DisplayMove: Equatable, Sendable {
        /// The screen the window moves to, as an index into `screens`.
        public var screenIndex: Int
        /// That screen's visible area.
        public var visibleFrame: CGRect
        /// The part of the visible area the window covers, on both screens.
        public var unit: UnitRect
        /// The window's frame on the new screen.
        public var frame: CGRect
    }

    /// Where a window goes when it moves to the previous or next display: the same part
    /// of the new screen's visible area as it covers on its own screen, so its size
    /// scales with the screen and it always ends up fully inside the visible area.
    /// Nil when there is no other screen.
    ///
    /// - Parameter knownUnit: the part of the visible area the window was last given, when
    ///   the caller knows it. It is used instead of measuring the frame, which keeps a
    ///   window exact over repeated moves even when a screen did not let it take the
    ///   whole frame it was given.
    public func move(
        windowFrame: CGRect,
        to direction: DisplayDirection,
        covering knownUnit: UnitRect? = nil
    ) -> DisplayMove? {
        guard let source = screenIndex(forWindowFrame: windowFrame),
              let destination = screenIndex(direction, from: source)
        else {
            return nil
        }
        let unit = knownUnit ?? PlacementGeometry.unitRect(of: windowFrame, in: screens[source].visibleFrame)
        let visibleFrame = screens[destination].visibleFrame
        return DisplayMove(
            screenIndex: destination,
            visibleFrame: visibleFrame,
            unit: unit,
            frame: PlacementGeometry.frame(for: unit, in: visibleFrame)
        )
    }
}
