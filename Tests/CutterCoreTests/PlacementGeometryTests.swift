import CoreGraphics
import Testing

@testable import CutterCore

private func unit(_ action: WindowAction) -> UnitRect {
    guard case .place(let unit) = action.behavior else {
        fatalError("\(action) is not a placement")
    }
    return unit
}

private func frame(_ action: WindowAction, in visibleFrame: CGRect) -> CGRect {
    PlacementGeometry.frame(for: unit(action), in: visibleFrame)
}

private let placements = WindowAction.allCases.filter { action in
    if case .place = action.behavior {
        return true
    }
    return false
}

@Suite struct PlacementFrameTests {
    /// A MacBook screen below its menu bar, with the Dock at the bottom.
    let visible = CGRect(x: 0, y: 33, width: 1728, height: 994)

    @Test func maximizeFillsTheVisibleArea() {
        #expect(frame(.maximize, in: visible) == visible)
    }

    @Test func halves() {
        #expect(frame(.leftHalf, in: visible) == CGRect(x: 0, y: 33, width: 864, height: 994))
        #expect(frame(.rightHalf, in: visible) == CGRect(x: 864, y: 33, width: 864, height: 994))
        #expect(frame(.topHalf, in: visible) == CGRect(x: 0, y: 33, width: 1728, height: 497))
        #expect(frame(.bottomHalf, in: visible) == CGRect(x: 0, y: 530, width: 1728, height: 497))
    }

    @Test func corners() {
        #expect(frame(.topLeft, in: visible) == CGRect(x: 0, y: 33, width: 864, height: 497))
        #expect(frame(.topRight, in: visible) == CGRect(x: 864, y: 33, width: 864, height: 497))
        #expect(frame(.bottomLeft, in: visible) == CGRect(x: 0, y: 530, width: 864, height: 497))
        #expect(frame(.bottomRight, in: visible) == CGRect(x: 864, y: 530, width: 864, height: 497))
    }

    @Test func placementsUseTheScreenOrigin() {
        let external = CGRect(x: 1728, y: 0, width: 2560, height: 1080)
        #expect(frame(.rightHalf, in: external) == CGRect(x: 3008, y: 0, width: 1280, height: 1080))
        #expect(frame(.bottomLeft, in: external) == CGRect(x: 1728, y: 540, width: 1280, height: 540))

        let leftOfPrimary = CGRect(x: -1920, y: -200, width: 1920, height: 1055)
        #expect(frame(.leftHalf, in: leftOfPrimary) == CGRect(x: -1920, y: -200, width: 960, height: 1055))
    }

    @Test func oddSizesTileWithoutGapOrOverlap() {
        let odd = CGRect(x: 0, y: 25, width: 1365, height: 743)
        let left = frame(.leftHalf, in: odd)
        let right = frame(.rightHalf, in: odd)
        #expect(left.maxX == right.minX)
        #expect(left.minX == odd.minX)
        #expect(right.maxX == odd.maxX)

        let top = frame(.topHalf, in: odd)
        let bottom = frame(.bottomHalf, in: odd)
        #expect(top.maxY == bottom.minY)
        #expect(top.minY == odd.minY)
        #expect(bottom.maxY == odd.maxY)

        let corners = [WindowAction.topLeft, .topRight, .bottomLeft, .bottomRight].map { frame($0, in: odd) }
        let area = corners.reduce(0) { $0 + $1.width * $1.height }
        #expect(area == odd.width * odd.height)
    }

    @Test(arguments: placements)
    func everyPlacementIsWholePointsInsideTheVisibleArea(action: WindowAction) {
        let odd = CGRect(x: 13, y: 25, width: 1365, height: 743)
        let result = frame(action, in: odd)
        #expect(odd.contains(result))
        #expect(result.width > 0)
        #expect(result.height > 0)
        for value in [result.minX, result.minY, result.width, result.height] {
            #expect(value == value.rounded())
        }
    }
}

@Suite struct CoordinateTests {
    @Test func flipsCocoaFramesToTopLeftOrigin() {
        // Primary screen, 1117 points high: menu bar 33 at the top, Dock 90 at the bottom.
        let visible = PlacementGeometry.flipped(
            CGRect(x: 0, y: 90, width: 1728, height: 994),
            primaryScreenHeight: 1117
        )
        #expect(visible == CGRect(x: 0, y: 33, width: 1728, height: 994))
    }

    @Test func flippingTwiceIsTheIdentity() {
        let rect = CGRect(x: 1728, y: 37, width: 2560, height: 1080)
        let there = PlacementGeometry.flipped(rect, primaryScreenHeight: 1117)
        #expect(PlacementGeometry.flipped(there, primaryScreenHeight: 1117) == rect)
    }
}

@Suite struct ScreenSelectionTests {
    /// The layout of the Mac this was developed on: a built-in display and an external
    /// one to its right, in Cocoa coordinates as `NSScreen` reports them.
    let layout = ScreenLayout(cocoaScreens: [
        (frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
         visibleFrame: CGRect(x: 0, y: 90, width: 1728, height: 994)),
        (frame: CGRect(x: 1728, y: 37, width: 2560, height: 1080),
         visibleFrame: CGRect(x: 1728, y: 37, width: 2560, height: 1080)),
    ])

    @Test func convertsScreensToTopLeftOrigin() {
        #expect(layout.screens[0].frame == CGRect(x: 0, y: 0, width: 1728, height: 1117))
        #expect(layout.screens[0].visibleFrame == CGRect(x: 0, y: 33, width: 1728, height: 994))
        #expect(layout.screens[1].frame == CGRect(x: 1728, y: 0, width: 2560, height: 1080))
        #expect(layout.screens[1].visibleFrame == CGRect(x: 1728, y: 0, width: 2560, height: 1080))
    }

    @Test func windowOnThePrimaryScreen() {
        let window = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(layout.visibleFrame(forWindowFrame: window) == layout.screens[0].visibleFrame)
    }

    @Test func windowOnTheExternalScreen() {
        let window = CGRect(x: 2000, y: 100, width: 800, height: 600)
        #expect(layout.visibleFrame(forWindowFrame: window) == layout.screens[1].visibleFrame)
    }

    @Test func windowAcrossTwoScreensUsesTheOneShowingMostOfIt() {
        let mostlyExternal = CGRect(x: 1600, y: 100, width: 800, height: 600)
        #expect(layout.visibleFrame(forWindowFrame: mostlyExternal) == layout.screens[1].visibleFrame)

        let mostlyPrimary = CGRect(x: 1000, y: 100, width: 800, height: 600)
        #expect(layout.visibleFrame(forWindowFrame: mostlyPrimary) == layout.screens[0].visibleFrame)
    }

    @Test func offScreenWindowUsesTheNearestScreen() {
        let farRight = CGRect(x: 6000, y: 100, width: 800, height: 600)
        #expect(layout.visibleFrame(forWindowFrame: farRight) == layout.screens[1].visibleFrame)

        let farLeft = CGRect(x: -3000, y: 100, width: 800, height: 600)
        #expect(layout.visibleFrame(forWindowFrame: farLeft) == layout.screens[0].visibleFrame)
    }

    @Test func noScreens() {
        let empty = ScreenLayout(cocoaScreens: [])
        #expect(empty.visibleFrame(forWindowFrame: CGRect(x: 0, y: 0, width: 10, height: 10)) == nil)
        #expect(PlacementGeometry.screenIndex(forWindowFrame: .zero, screenFrames: []) == nil)
    }

    @Test func placementLandsOnTheWindowsOwnScreen() {
        let window = CGRect(x: 2000, y: 100, width: 800, height: 600)
        let visible = layout.visibleFrame(forWindowFrame: window)!
        #expect(frame(.leftHalf, in: visible) == CGRect(x: 1728, y: 0, width: 1280, height: 1080))
    }
}

@Suite struct SettledOriginTests {
    let visible = CGRect(x: 0, y: 33, width: 1728, height: 994)

    private func settled(_ action: WindowAction, actualSize: CGSize) -> CGPoint {
        PlacementGeometry.settledOrigin(
            for: unit(action),
            target: frame(action, in: visible),
            actualSize: actualSize,
            visibleFrame: visible
        )
    }

    @Test func aWindowThatTookTheTargetSizeStaysAtTheTarget() {
        for action in placements {
            let target = frame(action, in: visible)
            #expect(settled(action, actualSize: target.size) == target.origin)
        }
    }

    @Test func rightHalfWiderThanHalfKeepsItsRightEdge() {
        let origin = settled(.rightHalf, actualSize: CGSize(width: 1000, height: 994))
        #expect(origin == CGPoint(x: 728, y: 33))
    }

    @Test func leftHalfWiderThanHalfKeepsItsLeftEdge() {
        let origin = settled(.leftHalf, actualSize: CGSize(width: 1000, height: 994))
        #expect(origin == CGPoint(x: 0, y: 33))
    }

    @Test func bottomRightSmallerThanTheCornerHugsTheCorner() {
        let origin = settled(.bottomRight, actualSize: CGSize(width: 400, height: 300))
        #expect(origin == CGPoint(x: 1328, y: 727))
    }

    @Test func fixedSizeWindowIsCentredWhenMaximized() {
        let origin = settled(.maximize, actualSize: CGSize(width: 728, height: 494))
        #expect(origin == CGPoint(x: 500, y: 283))
    }

    /// Seen on a real screen: macOS gave a full-height window 993 of the 994 points.
    @Test func windowOnePointShortStaysAgainstTheTopEdge() {
        #expect(settled(.maximize, actualSize: CGSize(width: 1728, height: 993)) == CGPoint(x: 0, y: 33))
        #expect(settled(.leftHalf, actualSize: CGSize(width: 864, height: 993)) == CGPoint(x: 0, y: 33))
        #expect(settled(.rightHalf, actualSize: CGSize(width: 864, height: 993)) == CGPoint(x: 864, y: 33))
    }

    @Test func windowLargerThanTheScreenKeepsItsTopLeftCornerVisible() {
        let origin = settled(.bottomRight, actualSize: CGSize(width: 2000, height: 1200))
        #expect(origin == CGPoint(x: 0, y: 33))
    }
}
