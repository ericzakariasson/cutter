import AppKit
import ApplicationServices
import CutterCore

/// Checks window placement end to end without touching anyone's windows: on every screen
/// it opens a small window in a helper process, applies each placement to it through the
/// same Accessibility code the shortcuts use, and compares where the window ended up with
/// where it should be.
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

        for (index, screen) in layout.screens.enumerated() {
            print("Screen \(index + 1): usable area \(describe(screen.visibleFrame))")

            let host = Process()
            host.executableURL = executable
            host.arguments = ["--self-test-window", String(index)]
            // The helper quits when this pipe closes, so it cannot outlive the test.
            host.standardInput = Pipe()
            do {
                try host.run()
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
            _ = FileHandle.standardInput.readDataToEndOfFile()
            exit(0)
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
