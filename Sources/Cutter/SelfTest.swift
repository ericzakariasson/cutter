import AppKit
import ApplicationServices
import CutterCore

/// Checks window placement end to end without touching anyone's windows: on every screen
/// it opens a small window in a helper process, applies each placement to it through the
/// same Accessibility code the shortcuts use, and compares where the window ended up with
/// where it should be. It then makes the helper stop responding and checks that Cutter
/// gives up on it quickly, and with several screens it sends a window around all of them.
///
/// Accessibility access belongs to the app, not to a terminal, so run it through `open`:
///
///     open -n build/Cutter.app --stdout /tmp/cutter-self-test.log --args --self-test
///     cat /tmp/cutter-self-test.log
enum SelfTest {
    private static let windowTitle = "Cutter self-test (closes by itself)"

    static func run() -> Int32 {
        guard AXIsProcessTrusted() else {
            print("Self-test not run: Accessibility access is not allowed for this process.")
            print("Grant access to Cutter first, and start the self-test with `open` rather than from a terminal.")
            return 1
        }
        guard let executable = Bundle.main.executableURL else {
            print("Self-test not run: cannot find Cutter's own executable.")
            return 1
        }

        let manager = WindowManager()
        let layout = ScreenLayout(cocoaScreens: NSScreen.screens.map { ($0.frame, $0.visibleFrame) })
        var failures = 0
        var skippedScreens = 0
        var checkedUnresponsiveApp = false

        for (index, screen) in layout.screens.enumerated() {
            print("Screen \(index + 1): usable area \(describe(screen.visibleFrame))")

            let host: Process
            let commands: Pipe
            do {
                (host, commands) = try launchHost(executable, screenIndex: index)
            } catch {
                print("  FAIL  could not start the test window: \(error.localizedDescription)")
                failures += 1
                continue
            }
            defer {
                host.terminate()
                host.waitUntilExit()
            }

            guard let window = waitForWindow(of: host.processIdentifier, manager: manager) else {
                print("  FAIL  could not find the test window through the Accessibility API")
                failures += 1
                continue
            }

            // macOS opens a window elsewhere when this screen shows a full-screen app.
            guard let start = try? manager.frame(of: window),
                  layout.visibleFrame(forWindowFrame: start) == screen.visibleFrame
            else {
                print("  skipped: the test window did not open on this screen (is it showing a full-screen app?)")
                skippedScreens += 1
                continue
            }

            for action in WindowAction.allCases {
                guard case .place(let unit) = action.behavior else {
                    continue
                }
                let expected = PlacementGeometry.frame(for: unit, in: screen.visibleFrame)
                let title = action.title.padding(toLength: 14, withPad: " ", startingAt: 0)
                do {
                    try manager.perform(action, on: window)
                    Thread.sleep(forTimeInterval: 0.2)
                    let reported = try manager.frame(of: window)
                    // The window server's view of the window, independent of the Accessibility API.
                    let onScreen = windowServerFrame(of: host.processIdentifier) ?? .null
                    let offBy = max(deviation(reported, expected), deviation(onScreen, expected))

                    if offBy == 0 {
                        print("  ok    \(title)\(describe(expected))")
                    } else if offBy <= tolerance {
                        // macOS can give a full-height window a point less than asked for.
                        print("  ok    \(title)wanted \(describe(expected)), got \(describe(onScreen)), Accessibility reports \(describe(reported)) (within \(Int(tolerance)) pt)")
                    } else {
                        failures += 1
                        print("  FAIL  \(title)wanted \(describe(expected)), got \(describe(onScreen)), Accessibility reports \(describe(reported))")
                    }
                } catch {
                    failures += 1
                    print("  FAIL  \(title)\(error)")
                }
            }

            if !checkedUnresponsiveApp {
                checkedUnresponsiveApp = true
                commands.fileHandleForWriting.write(Data("hang\n".utf8))
                Thread.sleep(forTimeInterval: 0.5)
                if !givesUpQuickly(manager: manager, window: window, pid: host.processIdentifier) {
                    failures += 1
                }
            }
        }

        if layout.screens.count < 2 {
            print("Display moves: not checked, there is only one screen.")
        } else if skippedScreens == layout.screens.count {
            print("Display moves: not checked, no screen accepted a test window.")
        } else {
            failures += checkDisplayMoves(executable: executable, manager: manager, layout: layout)
        }

        if failures > 0 {
            print("Self-test failed: \(failures) problem(s).")
            return 1
        }
        if skippedScreens == layout.screens.count {
            print("Self-test could not run: no screen accepted a test window.")
            return 1
        }
        print(skippedScreens == 0 ? "Self-test passed." : "Self-test passed on the screens it could use; \(skippedScreens) skipped.")
        return 0
    }

    private static func launchHost(_ executable: URL, screenIndex: Int) throws -> (Process, Pipe) {
        let host = Process()
        host.executableURL = executable
        host.arguments = ["--self-test-window", String(screenIndex)]
        // The helper quits when this pipe closes, so it cannot outlive the test.
        let commands = Pipe()
        host.standardInput = commands
        try host.run()
        return (host, commands)
    }

    /// Sends a window once around all the displays with "next display", then one step back
    /// with "previous display", for a few starting placements. After every step the window
    /// must cover the same part of the screen it landed on, and after the full round it
    /// must be exactly where it started. Returns the number of failures.
    private static func checkDisplayMoves(executable: URL, manager: WindowManager, layout: ScreenLayout) -> Int {
        let order = layout.displayOrder
        print("Display moves, in the order of screens \(order.map { String($0 + 1) }.joined(separator: ", ")):")

        guard let (host, _) = try? launchHost(executable, screenIndex: order[0]) else {
            print("  FAIL  could not start the test window")
            return 1
        }
        defer {
            host.terminate()
            host.waitUntilExit()
        }
        guard let window = waitForWindow(of: host.processIdentifier, manager: manager) else {
            print("  FAIL  could not find the test window through the Accessibility API")
            return 1
        }

        var failures = 0
        for placement in [WindowAction.maximize, .leftHalf, .bottomRight] {
            guard case .place(let unit) = placement.behavior else {
                continue
            }
            do {
                try manager.perform(placement, on: window)
                Thread.sleep(forTimeInterval: 0.3)
                let startFrame = windowServerFrame(of: host.processIdentifier) ?? .null
                // The window starts on whichever screen it is on: where macOS opened it,
                // or where the previous round left it.
                guard let startScreen = layout.screenIndex(forWindowFrame: startFrame),
                      var position = order.firstIndex(of: startScreen)
                else {
                    failures += 1
                    print("  FAIL  \(placement.title): the test window is on no screen")
                    continue
                }
                let steps = Array(repeating: WindowAction.nextDisplay, count: order.count) + [.previousDisplay]
                for (number, step) in steps.enumerated() {
                    position = (position + (step == .nextDisplay ? 1 : order.count - 1)) % order.count
                    let screen = layout.screens[order[position]]
                    let expected = PlacementGeometry.frame(for: unit, in: screen.visibleFrame)

                    try manager.perform(step, on: window)
                    Thread.sleep(forTimeInterval: 0.3)
                    let reported = try manager.frame(of: window)
                    let onScreen = windowServerFrame(of: host.processIdentifier) ?? .null
                    let label = "\(placement.title), \(step == .nextDisplay ? "next" : "previous") -> screen \(order[position] + 1)"

                    // A screen that reports no menu bar can still keep windows out of the
                    // strip where its hidden menu bar appears.
                    let hiddenMenuBar = screen.visibleFrame.minY == screen.frame.minY ? hiddenMenuBarAllowance : 0
                    let topInset = max(reported.minY, onScreen.minY) - expected.minY
                    var allowed = expected
                    if topInset > tolerance, topInset <= hiddenMenuBar, expected.minY == screen.visibleFrame.minY {
                        allowed = CGRect(x: expected.minX, y: expected.minY + topInset, width: expected.width, height: expected.height - topInset)
                    }
                    let backAtStart = number == order.count - 1
                    let offBy = backAtStart
                        ? deviation(onScreen, startFrame)
                        : max(deviation(reported, allowed), deviation(onScreen, allowed))

                    if offBy > tolerance {
                        failures += 1
                        let wanted = backAtStart ? startFrame : expected
                        print("  FAIL  \(label): wanted \(describe(wanted)), got \(describe(onScreen)), Accessibility reports \(describe(reported))")
                    } else if backAtStart {
                        print("  ok    \(label): \(describe(onScreen)), back where it started")
                    } else if allowed != expected {
                        print("  ok    \(label): \(describe(onScreen)), \(Int(topInset)) pt below the top where a hidden menu bar sits")
                    } else {
                        print("  ok    \(label): \(describe(onScreen))")
                    }
                }
            } catch {
                failures += 1
                print("  FAIL  \(placement.title): \(error)")
            }
        }
        return failures
    }

    /// How far below the top of a screen without a visible menu bar a window may end up.
    private static let hiddenMenuBarAllowance: CGFloat = 40

    /// A shortcut runs on Cutter's main thread, so an app that has stopped responding must
    /// not hold it up for long. The helper's main thread is blocked at this point.
    private static func givesUpQuickly(manager: WindowManager, window: AXUIElement, pid: pid_t) -> Bool {
        func seconds(_ body: () throws -> Void) -> (elapsed: TimeInterval, failed: Bool) {
            let start = Date()
            do {
                try body()
                return (Date().timeIntervalSince(start), false)
            } catch {
                return (Date().timeIntervalSince(start), true)
            }
        }

        let placing = seconds { try manager.perform(.leftHalf, on: window) }
        let finding = seconds { _ = try manager.focusedWindow(ofProcess: pid) }
        let passed = placing.failed && finding.failed && placing.elapsed <= patience && finding.elapsed <= patience
        print(String(
            format: "  %@  Unresponsive app: placing gave up after %.1f s, finding its window after %.1f s (limit %.1f s each)",
            passed ? "ok  " : "FAIL",
            placing.elapsed,
            finding.elapsed,
            patience
        ))
        return passed
    }

    /// The longest a single action may wait for an app that does not answer.
    private static let patience: TimeInterval = 1.5

    /// How far a window may be from the exact frame, in points, and still count as placed.
    private static let tolerance: CGFloat = 2

    /// The largest difference between any edge of two frames.
    private static func deviation(_ a: CGRect, _ b: CGRect) -> CGFloat {
        guard !a.isNull, !b.isNull else {
            return .infinity
        }
        return [a.minX - b.minX, a.minY - b.minY, a.maxX - b.maxX, a.maxY - b.maxY].map(abs).max() ?? 0
    }

    /// The helper process: shows one window in the middle of a screen until its standard
    /// input closes.
    static func runWindowHost(screenIndex: String?) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let screens = NSScreen.screens
        guard let index = screenIndex.flatMap(Int.init), screens.indices.contains(index) else {
            return 2
        }
        let visible = screens[index].visibleFrame
        let window = NSWindow(
            contentRect: NSRect(x: visible.midX - 200, y: visible.midY - 150, width: 400, height: 300),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        // In front, but without taking keyboard focus from the app in use.
        window.orderFrontRegardless()

        DispatchQueue.global().async {
            while true {
                let data = FileHandle.standardInput.availableData
                if data.isEmpty {
                    exit(0)
                }
                if String(decoding: data, as: UTF8.self).contains("hang") {
                    // Stop answering, the way a beach-balling app does.
                    DispatchQueue.main.async {
                        Thread.sleep(forTimeInterval: 60)
                    }
                }
            }
        }
        app.run()
        return 0
    }

    private static func waitForWindow(of pid: pid_t, manager: WindowManager) -> AXUIElement? {
        for _ in 0..<50 {
            if let window = manager.window(titled: windowTitle, inProcess: pid) {
                return window
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    private static func windowServerFrame(of pid: pid_t) -> CGRect? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds)
            else {
                continue
            }
            return frame
        }
        return nil
    }

    private static func describe(_ rect: CGRect) -> String {
        guard !rect.isNull else {
            return "no window on screen"
        }
        func number(_ value: CGFloat) -> String {
            value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        }
        return "\(number(rect.width))x\(number(rect.height)) at (\(number(rect.minX)), \(number(rect.minY)))"
    }
}
