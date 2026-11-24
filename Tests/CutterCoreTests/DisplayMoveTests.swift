import CoreGraphics
import Testing

@testable import CutterCore

/// A screen in Cocoa coordinates, as `NSScreen` reports it, with a name for readable tests.
private struct Display {
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect

    /// A display with a 33-point menu bar and no Dock.
    init(_ name: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.name = name
        self.frame = CGRect(x: x, y: y, width: width, height: height)
        self.visibleFrame = CGRect(x: x, y: y, width: width, height: height - 33)
    }
}

/// The first display is the primary one, as in `NSScreen.screens`.
private func layout(_ displays: [Display]) -> ScreenLayout {
    ScreenLayout(cocoaScreens: displays.map { ($0.frame, $0.visibleFrame) })
}

private func names(_ displays: [Display]) -> [String] {
    layout(displays).displayOrder.map { displays[$0].name }
}

/// The names of the displays a window visits when the same move is repeated.
private func visits(_ displays: [Display], from start: String, _ direction: DisplayDirection, steps: Int) -> [String] {
    let layout = layout(displays)
    var index = displays.firstIndex { $0.name == start }!
    var visited: [String] = []
    for _ in 0..<steps {
        index = layout.screenIndex(direction, from: index)!
        visited.append(displays[index].name)
    }
    return visited
}

// The Mac this was built on: a laptop with a wider display arranged above it.
private let laptop = Display("laptop", x: 0, y: 0, width: 1728, height: 1117)
private let above = Display("above", x: -458, y: 1117, width: 3200, height: 1350)
private let stacked = [laptop, above]

@Suite struct DisplayOrderTests {
    @Test func stackedDisplaysGoFromTopToBottom() {
        #expect(names(stacked) == ["above", "laptop"])
    }

    @Test func withStackedDisplaysPreviousIsTheOneAboveAndNextTheOneBelow() {
        #expect(visits(stacked, from: "laptop", .previous, steps: 1) == ["above"])
        #expect(visits(stacked, from: "above", .next, steps: 1) == ["laptop"])
    }

    @Test func sideBySideDisplaysGoFromLeftToRight() {
        let right = Display("right", x: 1728, y: 37, width: 2560, height: 1080)
        #expect(names([laptop, right]) == ["laptop", "right"])

        let left = Display("left", x: -2560, y: 37, width: 2560, height: 1080)
        #expect(names([laptop, left]) == ["left", "laptop"])
    }

    @Test func sideBySideDisplaysOfDifferentHeightsShareARow() {
        // A portrait display next to the laptop, its top far above the laptop's.
        let portrait = Display("portrait", x: 1728, y: -400, width: 1440, height: 2560)
        #expect(names([laptop, portrait]) == ["laptop", "portrait"])

        // A small display next to a big one, hanging from its top edge.
        let big = Display("big", x: 0, y: 0, width: 3840, height: 2160)
        let small = Display("small", x: -1280, y: 1440, width: 1280, height: 720)
        #expect(names([big, small]) == ["small", "big"])
    }

    @Test func aRowOfTwoAboveOneReadsLikeText() {
        let topLeft = Display("top left", x: 0, y: 1117, width: 1920, height: 1080)
        let topRight = Display("top right", x: 1920, y: 1117, width: 1920, height: 1080)
        #expect(names([laptop, topRight, topLeft]) == ["top left", "top right", "laptop"])
    }

    @Test func aTwoByTwoGridReadsLikeText() {
        let a = Display("a", x: 0, y: 1080, width: 1920, height: 1080)
        let b = Display("b", x: 1920, y: 1080, width: 1920, height: 1080)
        let c = Display("c", x: 0, y: 0, width: 1920, height: 1080)
        let d = Display("d", x: 1920, y: 0, width: 1920, height: 1080)
        #expect(names([c, d, a, b]) == ["a", "b", "c", "d"])
        #expect(names([b, a, d, c]) == ["a", "b", "c", "d"])
    }

    @Test func theOrderDoesNotDependOnWhichDisplayIsPrimary() {
        // The same desks, with the display above made the primary one: Cocoa coordinates
        // then start at its corner, and it comes first in the list.
        let primaryAbove = Display("above", x: 0, y: 0, width: 3200, height: 1350)
        let laptopBelow = Display("laptop", x: 458, y: -1117, width: 1728, height: 1117)
        #expect(names([primaryAbove, laptopBelow]) == names(stacked))
    }

    @Test func nextCyclesThroughEveryDisplayAndWrapsAround() {
        let left = Display("left", x: -1920, y: 0, width: 1920, height: 1080)
        let right = Display("right", x: 1728, y: 0, width: 1920, height: 1080)
        let displays = [laptop, right, left, above]
        #expect(names(displays) == ["above", "left", "laptop", "right"])

        #expect(visits(displays, from: "laptop", .next, steps: 5) == ["right", "above", "left", "laptop", "right"])
        #expect(visits(displays, from: "laptop", .previous, steps: 5) == ["left", "above", "right", "laptop", "left"])
    }

    @Test func withTwoDisplaysBothDirectionsSwap() {
        #expect(visits(stacked, from: "laptop", .next, steps: 3) == ["above", "laptop", "above"])
        #expect(visits(stacked, from: "above", .previous, steps: 3) == ["laptop", "above", "laptop"])
    }

    @Test func withOneDisplayThereIsNowhereToGo() {
        let single = layout([laptop])
        #expect(single.displayOrder == [0])
        #expect(single.screenIndex(.next, from: 0) == nil)
        #expect(single.screenIndex(.previous, from: 0) == nil)
        #expect(single.move(windowFrame: CGRect(x: 100, y: 100, width: 800, height: 600), to: .next) == nil)

        let none = layout([])
        #expect(none.displayOrder == [])
        #expect(none.move(windowFrame: CGRect(x: 0, y: 0, width: 10, height: 10), to: .next) == nil)
    }
}

@Suite struct DisplayMoveFrameTests {
    // Top-left-origin coordinates. The laptop is 1728x1117 with a 33-point menu bar; the
    // display above it is 3200x1350, wider and taller, and starts 458 points to the left.
    let screens = layout(stacked)
    let laptopVisible = CGRect(x: 0, y: 33, width: 1728, height: 1084)
    let aboveVisible = CGRect(x: -458, y: -1317, width: 3200, height: 1317)

    private func frame(_ action: WindowAction, in visible: CGRect) -> CGRect {
        guard case .place(let unit) = action.behavior else {
            fatalError("\(action) is not a placement")
        }
        return PlacementGeometry.frame(for: unit, in: visible)
    }

    @Test func theFixtureHasTheVisibleAreasTheTestsAssume() {
        #expect(screens.screens[0].visibleFrame == laptopVisible)
        #expect(screens.screens[1].visibleFrame == aboveVisible)
    }

    @Test func aMaximizedWindowStaysMaximized() throws {
        let up = try #require(screens.move(windowFrame: laptopVisible, to: .previous))
        #expect(up.screenIndex == 1)
        #expect(up.frame == aboveVisible)

        let down = try #require(screens.move(windowFrame: aboveVisible, to: .next))
        #expect(down.screenIndex == 0)
        #expect(down.frame == laptopVisible)
    }

    @Test(arguments: [WindowAction.leftHalf, .rightHalf, .topHalf, .bottomHalf, .topLeft, .topRight, .bottomLeft, .bottomRight])
    func aPlacedWindowKeepsItsPlacementInBothDirections(action: WindowAction) throws {
        let up = try #require(screens.move(windowFrame: frame(action, in: laptopVisible), to: .previous))
        #expect(up.frame == frame(action, in: aboveVisible))

        let down = try #require(screens.move(windowFrame: frame(action, in: aboveVisible), to: .next))
        #expect(down.frame == frame(action, in: laptopVisible))
    }

    /// macOS gives a full-height window a point less than asked for. That must not add up
    /// to a window that is no longer maximized on the other display.
    @Test func aWindowAPointShortOfItsPlacementStillCountsAsPlaced() throws {
        let nearlyMaximized = CGRect(x: 0, y: 33, width: 1728, height: 1083)
        #expect(try #require(screens.move(windowFrame: nearlyMaximized, to: .previous)).frame == aboveVisible)

        let nearlyLeftHalf = CGRect(x: 0, y: 34, width: 863, height: 1083)
        #expect(try #require(screens.move(windowFrame: nearlyLeftHalf, to: .previous)).frame == frame(.leftHalf, in: aboveVisible))
    }

    /// Seen on a real display: it reported its whole frame as usable, but kept windows
    /// out of the 30 points where its hidden menu bar appears.
    @Test func aKnownPlacementIsUsedInsteadOfMeasuringWhereTheWindowLanded() throws {
        let landed = CGRect(x: aboveVisible.minX, y: aboveVisible.minY + 30, width: aboveVisible.width, height: aboveVisible.height - 30)

        let measured = try #require(screens.move(windowFrame: landed, to: .next))
        #expect(measured.frame != laptopVisible)

        let maximized = UnitRect(x: 0, y: 0, width: 1, height: 1)
        let known = try #require(screens.move(windowFrame: landed, to: .next, covering: maximized))
        #expect(known.frame == laptopVisible)
        #expect(known.unit == maximized)
    }

    @Test func aFreeWindowKeepsItsRelativePositionAndSize() throws {
        // A quarter of the way in from the left and top, half the width and height.
        let window = CGRect(x: 432, y: 304, width: 864, height: 542)
        let move = try #require(screens.move(windowFrame: window, to: .previous))
        #expect(move.unit == UnitRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(move.frame.minX == aboveVisible.minX + aboveVisible.width / 4)
        #expect(move.frame.width == aboveVisible.width / 2)
        #expect(abs(move.frame.minY - (aboveVisible.minY + aboveVisible.height / 4)) <= 1)
        #expect(abs(move.frame.height - aboveVisible.height / 2) <= 1)
    }

    @Test func movingThereAndBackReturnsTheWindowToWhereItWas() throws {
        let window = CGRect(x: 300, y: 200, width: 900, height: 620)
        let there = try #require(screens.move(windowFrame: window, to: .previous))
        let back = try #require(screens.move(windowFrame: there.frame, to: .next))
        #expect(back.screenIndex == 0)
        for (a, b) in [(back.frame.minX, window.minX), (back.frame.minY, window.minY), (back.frame.maxX, window.maxX), (back.frame.maxY, window.maxY)] {
            #expect(abs(a - b) <= 1)
        }
    }

    @Test func aWindowHangingOffItsScreenEndsUpFullyInsideTheOtherOne() throws {
        // Half of it is past the laptop's right edge, and it reaches under the menu bar.
        let window = CGRect(x: 1300, y: 10, width: 860, height: 600)
        let move = try #require(screens.move(windowFrame: window, to: .previous))
        #expect(aboveVisible.contains(move.frame))
        #expect(move.frame.maxX == aboveVisible.maxX)
        #expect(move.frame.minY == aboveVisible.minY)
    }

    @Test func aWindowLargerThanItsScreenFillsTheOtherOne() throws {
        let window = CGRect(x: -100, y: 0, width: 2400, height: 1400)
        let move = try #require(screens.move(windowFrame: window, to: .previous))
        #expect(move.frame == aboveVisible)
    }

    @Test(arguments: [
        CGRect(x: 0, y: 33, width: 1728, height: 1084),
        CGRect(x: 17, y: 51, width: 333, height: 207),
        CGRect(x: 1700, y: 1000, width: 400, height: 300),
        CGRect(x: -200, y: -50, width: 500, height: 400),
        CGRect(x: 863.5, y: 33, width: 864.5, height: 541.5),
    ])
    func theWindowAlwaysEndsUpInsideTheVisibleAreaInWholePoints(window: CGRect) throws {
        for direction in [DisplayDirection.previous, .next] {
            let move = try #require(screens.move(windowFrame: window, to: direction))
            #expect(aboveVisible.contains(move.frame))
            #expect(move.frame.width > 0)
            #expect(move.frame.height > 0)
            for value in [move.frame.minX, move.frame.minY, move.frame.width, move.frame.height] {
                #expect(value == value.rounded())
            }
        }
    }

    @Test func aWindowMovesFromTheScreenShowingMostOfIt() throws {
        // Mostly on the display above, with a strip reaching down onto the laptop.
        let window = CGRect(x: 200, y: -500, width: 800, height: 600)
        let move = try #require(screens.move(windowFrame: window, to: .next))
        #expect(move.screenIndex == 0)
        #expect(laptopVisible.contains(move.frame))
    }

    @Test func movingToASmallerDisplayShrinksTheWindowInProportion() throws {
        let window = CGRect(x: -458, y: -1317, width: 1600, height: 1317)
        let move = try #require(screens.move(windowFrame: window, to: .next))
        #expect(move.frame == frame(.leftHalf, in: laptopVisible))
    }
}

@Suite struct UnitRectTests {
    let visible = CGRect(x: 100, y: 50, width: 1000, height: 800)

    /// Fractions come out of a division, so compare them to within a rounding error.
    private func isClose(_ unit: UnitRect, to expected: UnitRect) -> Bool {
        zip([unit.x, unit.y, unit.width, unit.height], [expected.x, expected.y, expected.width, expected.height])
            .allSatisfy { abs($0 - $1) < 1e-9 }
    }

    @Test func measuresAWindowInFractionsOfTheVisibleArea() {
        let window = CGRect(x: 300, y: 250, width: 400, height: 200)
        let unit = PlacementGeometry.unitRect(of: window, in: visible)
        #expect(isClose(unit, to: UnitRect(x: 0.2, y: 0.25, width: 0.4, height: 0.25)))
    }

    @Test func edgesNearTheScreenEdgesAndCentreLinesSnapToThem() {
        let window = CGRect(x: 102, y: 51, width: 497, height: 797)
        #expect(PlacementGeometry.unitRect(of: window, in: visible) == UnitRect(x: 0, y: 0, width: 0.5, height: 1))
    }

    @Test func edgesFurtherAwayDoNotSnap() {
        let window = CGRect(x: 110, y: 60, width: 480, height: 780)
        let unit = PlacementGeometry.unitRect(of: window, in: visible)
        #expect(isClose(unit, to: UnitRect(x: 0.01, y: 0.0125, width: 0.48, height: 0.975)))
    }

    @Test func theResultStaysInsideTheUnitSquare() {
        for window in [
            CGRect(x: -500, y: -500, width: 300, height: 300),
            CGRect(x: 1050, y: 800, width: 300, height: 300),
            CGRect(x: 0, y: 0, width: 5000, height: 5000),
        ] {
            let unit = PlacementGeometry.unitRect(of: window, in: visible)
            #expect(unit.x >= 0)
            #expect(unit.y >= 0)
            #expect(unit.width > 0)
            #expect(unit.height > 0)
            #expect(unit.x + unit.width <= 1.000001)
            #expect(unit.y + unit.height <= 1.000001)
        }
    }

    @Test func aTinyWindowOnASnapLineKeepsItsSize() {
        let window = CGRect(x: 598, y: 448, width: 5, height: 5)
        let unit = PlacementGeometry.unitRect(of: window, in: visible)
        #expect(isClose(unit, to: UnitRect(x: 0.498, y: 0.4975, width: 0.005, height: 0.00625)))
    }
}
