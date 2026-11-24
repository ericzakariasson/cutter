import CoreGraphics
import CutterCore
import Foundation

/// What the demo clip shows: a window answering Cutter's default shortcuts, one after the
/// other, on a pair of drawn displays.
///
/// Nothing here decides where the window goes. Every frame comes from `CutterCore`, the
/// same code the app runs, and every shortcut from the app's defaults, so the clip cannot
/// show something the app does not do. Regenerate it when either changes.
struct DemoScript {
    struct Step: Equatable {
        let action: WindowAction
        let shortcut: KeyCombo
        /// The window's frame before and after, in the app's top-left coordinates.
        let from: CGRect
        let to: CGRect
    }

    let layout: ScreenLayout
    let steps: [Step]

    /// The actions shown, in order. With the laptop below the other display, ↑ sends the
    /// window up and ↓ brings it back, which also returns it to where the clip starts.
    static let actions: [WindowAction] = [.leftHalf, .rightHalf, .maximize, .previousDisplay, .nextDisplay]

    /// A laptop with a wider display arranged above it. The first screen is the primary
    /// one, as in the app. Menu bars are 33 and 30 points high, and the laptop has the
    /// Dock, which takes 80 points off the bottom of its visible area.
    static let displays = ScreenLayout(screens: [
        ScreenLayout.Screen(
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 0, y: 33, width: 1728, height: 1004)
        ),
        ScreenLayout.Screen(
            frame: CGRect(x: -736, y: -1350, width: 3200, height: 1350),
            visibleFrame: CGRect(x: -736, y: -1320, width: 3200, height: 1320)
        ),
    ])

    init(layout: ScreenLayout = DemoScript.displays, configuration: ShortcutConfiguration = ShortcutConfiguration()) {
        self.layout = layout

        // The clip starts with the window maximized on the primary screen.
        var window = Window(frame: layout.screens[0].visibleFrame, unit: nil)
        window.apply(.maximize, in: layout)

        var steps: [Step] = []
        for action in Self.actions {
            // An action without a default shortcut has no keys to show.
            guard let shortcut = configuration.shortcut(for: action) else {
                continue
            }
            let before = window.frame
            window.apply(action, in: layout)
            steps.append(Step(action: action, shortcut: shortcut, from: before, to: window.frame))
        }
        self.steps = steps
    }

    /// Whether the last step leaves the window where the first one finds it.
    var loops: Bool {
        guard let first = steps.first, let last = steps.last else {
            return true
        }
        return first.from == last.to
    }

    /// A window as the app sees it: its frame and, as `WindowManager` remembers, the part
    /// of the visible area it was last given.
    private struct Window {
        var frame: CGRect
        var unit: UnitRect?

        mutating func apply(_ action: WindowAction, in layout: ScreenLayout) {
            switch action.behavior {
            case .place(let unit):
                guard let visibleFrame = layout.visibleFrame(forWindowFrame: frame) else {
                    return
                }
                frame = PlacementGeometry.frame(for: unit, in: visibleFrame)
                self.unit = unit
            case .moveToDisplay(let direction):
                guard let move = layout.move(windowFrame: frame, to: direction, covering: unit) else {
                    return
                }
                frame = move.frame
                unit = move.unit
            case .toggleFullScreen:
                break
            }
        }
    }
}

/// When things happen in the clip, in seconds.
struct DemoTimeline {
    let script: DemoScript

    /// One step: the keys appear, are pressed, the window moves, and the result is held.
    static let stepDuration = 2.6
    private static let keysAppear = 0.0...0.22
    private static let keysPressed = 0.42...0.74
    private static let windowMoves = 0.5...1.0
    private static let keysLeave = 2.38...2.6

    var duration: Double {
        Double(script.steps.count) * Self.stepDuration
    }

    struct Moment {
        var windowFrame: CGRect
        /// The step whose keys are on screen, how visible they are and how far pressed.
        var step: DemoScript.Step
        var keysOpacity: Double
        var keysPressed: Double
    }

    func moment(at time: Double) -> Moment? {
        guard !script.steps.isEmpty else {
            return nil
        }
        let wrapped = time.truncatingRemainder(dividingBy: duration)
        let index = min(Int(wrapped / Self.stepDuration), script.steps.count - 1)
        let step = script.steps[index]
        let local = wrapped - Double(index) * Self.stepDuration

        let progress = Self.easeInOut(Self.fraction(local, in: Self.windowMoves))
        let frame = CGRect(
            x: Self.mix(step.from.minX, step.to.minX, progress),
            y: Self.mix(step.from.minY, step.to.minY, progress),
            width: Self.mix(step.from.width, step.to.width, progress),
            height: Self.mix(step.from.height, step.to.height, progress)
        )

        let opacity = min(Self.fraction(local, in: Self.keysAppear), 1 - Self.fraction(local, in: Self.keysLeave))
        let pressDown = Self.fraction(local, in: Self.keysPressed.lowerBound...(Self.keysPressed.lowerBound + 0.07))
        let pressUp = Self.fraction(local, in: Self.keysPressed.upperBound...(Self.keysPressed.upperBound + 0.1))
        return Moment(windowFrame: frame, step: step, keysOpacity: opacity, keysPressed: pressDown - pressUp)
    }

    private static func fraction(_ value: Double, in range: ClosedRange<Double>) -> Double {
        min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    private static func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }

    /// Slow start, slow stop, like a window settling into place.
    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
