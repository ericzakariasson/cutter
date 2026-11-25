import AppKit
import Combine
import SwiftUI

/// A panel that takes the keyboard without making Cutter the active app, the way
/// Spotlight does: the app the user was in stays frontmost and gets the keyboard back
/// when the panel closes.
final class KeyPanel: NSPanel {
    /// Gets every key press first; returns whether it used it.
    var onKeyDown: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true {
            return
        }
        super.sendEvent(event)
    }

    /// Key presses with ⌘ come here before anything else sees them. The panel uses its
    /// own and swallows the rest. Otherwise they would go on to Cutter's menu, and ⌘Q,
    /// meant for the app the user is looking at, would quit Cutter.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            _ = onKeyDown?(event)
        }
        return true
    }

    /// Escape arrives here as well when a view declines it.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Shows and hides the recent-screenshots panel.
final class ScreenshotPanelController: NSObject, NSWindowDelegate {
    let model: ScreenshotBrowserModel
    private let thumbnails = ThumbnailStore()
    private var panel: KeyPanel?
    private var clickMonitor: Any?
    private var stateObservation: AnyCancellable?

    override init() {
        model = ScreenshotBrowserModel()
        super.init()
        model.environment.close = { [weak self] in
            self?.close()
        }
        // If macOS asked about access while the folder was read, its question took the
        // keyboard. Take it back once the answer is in.
        stateObservation = model.$state.sink { [weak self] state in
            guard state != .loading else {
                return
            }
            DispatchQueue.main.async {
                if let panel = self?.panel, panel.isVisible, !panel.isKeyWindow {
                    panel.makeKey()
                }
            }
        }
    }

    var isShown: Bool {
        panel?.isVisible == true
    }

    /// The shortcut and the menu item both come here: show the panel, or close it when
    /// it is already up.
    func toggle() {
        if isShown {
            close()
        } else {
            show()
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // The screenshots are read here and nowhere else, so that the first use of the
        // panel is the moment macOS asks whether Cutter may read the folder.
        model.reload()

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(CGPoint(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.minY + (visible.height - size.height) * 0.6).rounded()
            ))
        }
        panel.makeKeyAndOrderFront(nil)
        if !panel.isKeyWindow {
            // Should not happen for a non-activating panel; activating the app is the
            // fallback that always gets the keyboard.
            NSLog("Cutter: the screenshots panel did not become key; activating Cutter")
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }

        // A click in another app closes the panel even if it never got the keyboard.
        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closeUnlessLoading()
            }
        }
    }

    func close() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        closeUnlessLoading()
    }

    /// While the folder is being read for the first time, macOS may be showing its own
    /// question about access, which takes the keyboard away. The panel waits for the
    /// answer instead of disappearing behind it.
    private func closeUnlessLoading() {
        if model.state != .loading {
            close()
        }
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(
            contentRect: NSRect(origin: .zero, size: ScreenshotBrowserView.size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        // On whichever Space is in front, and over full-screen apps.
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.onCancel = { [weak self] in
            self?.close()
        }
        panel.onKeyDown = { [weak self] event in
            guard let self, let command = ScreenshotBrowserModel.command(for: event) else {
                return false
            }
            self.model.perform(command)
            return true
        }

        let hostingView = NSHostingView(rootView: ScreenshotBrowserView(model: model, thumbnails: thumbnails))
        hostingView.frame = NSRect(origin: .zero, size: ScreenshotBrowserView.size)
        panel.contentView = hostingView
        return panel
    }
}
