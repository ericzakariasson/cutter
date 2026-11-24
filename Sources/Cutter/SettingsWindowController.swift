import AppKit
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var sizeObservation: NSKeyValueObservation?

    private(set) lazy var window: NSWindow = makeWindow()

    init(model: AppModel) {
        self.model = model
    }

    /// Shows the settings window. Pass `activating: false` to bring it up without taking
    /// keyboard focus from the app the user is typing in.
    func show(activating: Bool) {
        if activating {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.recorder.cancel()
    }

    private func makeWindow() -> NSWindow {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let view = SettingsView(
            model: model,
            permission: model.permission,
            recorder: model.recorder,
            loginItem: model.loginItem,
            maxHeight: max(screenHeight - 80, 300)
        )
        let hostingController = NSHostingController(rootView: view)
        hostingController.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Cutter Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(hostingController.view.fittingSize)
        if let screen = NSScreen.main {
            // Centred on the screen the user is working on, a little above the middle.
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(CGPoint(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.minY + (visible.height - size.height) * 2 / 3).rounded()
            ))
        }

        // The content changes height, most visibly when the Accessibility notice goes
        // away. Follow it, keeping the title bar where it is.
        sizeObservation = hostingController.observe(\.preferredContentSize, options: [.new]) { [weak window] controller, _ in
            guard let window else {
                return
            }
            let size = controller.preferredContentSize
            guard size.width > 0, size.height > 0, size != window.contentLayoutRect.size else {
                return
            }
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            window.setFrame(frame, display: true)
        }
        return window
    }
}
