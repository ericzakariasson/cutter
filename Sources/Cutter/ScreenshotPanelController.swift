import AppKit
import SwiftUI

/// A panel that takes the keyboard without making Cutter the active app, the way
/// Spotlight does: the app the user was in stays frontmost and gets the keyboard back
/// when the panel closes.
final class KeyPanel: NSPanel {
    /// Gets every key press first; returns whether it used it.
    var onKeyDown: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?
    /// For tests, which cannot put the panel on screen.
    var holdsKeyboardOverride: Bool?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The panel acts on keys only while it is visibly open and has the keyboard. A
    /// hidden panel must never use or stop a key press.
    var holdsKeyboard: Bool {
        holdsKeyboardOverride ?? (isVisible && isKeyWindow)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, holdsKeyboard, onKeyDown?(event) == true {
            return
        }
        super.sendEvent(event)
    }

    /// Key presses with ⌘ come here before anything else sees them. While the panel is
    /// open it uses its own and stops the rest: they would otherwise go on to Cutter's
    /// menu, and ⌘Q, meant for the app the user is looking at, would quit Cutter.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard holdsKeyboard else {
            return super.performKeyEquivalent(with: event)
        }
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
///
/// The panel holds the keyboard while it is open, so the rule here is to let go at the
/// first sign that the user's attention is elsewhere. It closes when it loses the
/// keyboard for any reason, on a click anywhere else, when another app comes forward,
/// when a drag out of it ends, and when reading the folder takes too long. It never
/// takes the keyboard back by itself and never makes Cutter the active app.
final class ScreenshotPanelController: NSObject, NSWindowDelegate {
    enum CloseReason: String {
        /// Escape, ⌘W, or after Open, Copy or Show in Finder.
        case command
        /// The panel's own shortcut or menu item, used while it is open.
        case toggledOff
        case lostKeyboard
        case clickElsewhere
        case otherAppCameForward
        case cutterDeactivated
        case dragEnded
        case slowLoading
        case sleep
    }

    /// How long the panel waits for the folder to be read before it gives up. Reading
    /// takes milliseconds, except when macOS is asking whether Cutter may read the folder.
    static let loadingPatience: TimeInterval = 4

    let model: ScreenshotBrowserModel
    /// Called after each close, with why. For tests and the log.
    var onClose: ((CloseReason) -> Void)?
    /// Whether a mouse button is held, which is how the end of a drag is noticed.
    var isMouseButtonDown: () -> Bool = { NSEvent.pressedMouseButtons != 0 }
    /// Tests turn this off: a real click or app switch on the Mac running them must not
    /// decide their outcome.
    var listensToTheSystem = true

    private(set) var isOpen = false
    private let thumbnails = ThumbnailStore()
    private let markup = ScreenshotMarkupController()
    private var panel: KeyPanel?
    private var clickMonitor: Any?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var loadingTimer: Timer?
    private var dragTimer: Timer?

    override init() {
        model = ScreenshotBrowserModel()
        super.init()
        model.environment.close = { [weak self] in
            self?.close(.command)
        }
        model.environment.dragBegan = { [weak self] in
            self?.dragBegan()
        }
        model.environment.edit = { [weak self] file in
            self?.markup.edit(file)
        }
        markup.onSaved = { [weak self] _ in
            self?.thumbnails.forgetEverything()
            self?.model.picturesChanged()
        }
    }

    /// The shortcut and the menu item both come here: show the panel, or close it when
    /// it is already up.
    func toggle() {
        if isOpen {
            close(.toggledOff)
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
        if panel.hasShadow {
            // The shadow follows the sheet's shape, which is only known once it is on screen.
            panel.invalidateShadow()
        }
        // The log says when the panel had the keyboard and why it let go, and nothing
        // about the screenshots.
        NSLog("Cutter: screenshots panel opened%@", panel.isKeyWindow ? "" : " without the keyboard; the mouse still works in it")
        beginSession()
    }

    /// Starts watching for every reason to close. Separate from `show()` so that tests
    /// can exercise the rules without putting a panel on screen.
    func beginSession() {
        endSession()
        isOpen = true

        let timer = Timer(timeInterval: Self.loadingPatience, repeats: false) { [weak self] _ in
            self?.loadingPatienceRanOut()
        }
        RunLoop.main.add(timer, forMode: .common)
        loadingTimer = timer

        guard listensToTheSystem else {
            return
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.close(.clickElsewhere)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.appCameForward(processIdentifier: app?.processIdentifier)
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(workspace, name) { [weak self] _ in
                self?.close(.sleep)
            }
        }
        observe(.default, NSApplication.didResignActiveNotification) { [weak self] _ in
            self?.close(.cutterDeactivated)
        }
    }

    /// Hides the panel and stops everything that was watching for it. Safe to call at
    /// any time and more than once.
    func close(_ reason: CloseReason) {
        guard isOpen else {
            return
        }
        endSession()
        if let panel {
            panel.orderOut(nil)
            giveBackTheKeyboard(after: panel)
            NSLog("Cutter: screenshots panel closed (%@)", reason.rawValue)
        }
        onClose?(reason)
    }

    // MARK: - Reasons to close

    func windowDidResignKey(_ notification: Notification) {
        close(.lostKeyboard)
    }

    func appCameForward(processIdentifier: pid_t?) {
        if processIdentifier != ProcessInfo.processInfo.processIdentifier {
            close(.otherAppCameForward)
        }
    }

    func loadingPatienceRanOut() {
        if model.state == .loading {
            close(.slowLoading)
        }
    }

    /// A drag out of the panel involves no click elsewhere and leaves the panel holding
    /// the keyboard, while the user's next move is in the app the screenshot went to. So
    /// the panel closes once the mouse button is let go.
    func dragBegan() {
        guard isOpen, dragTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkWhetherDragEnded()
        }
        RunLoop.main.add(timer, forMode: .common)
        dragTimer = timer
    }

    func checkWhetherDragEnded() {
        if dragTimer != nil, !isMouseButtonDown() {
            close(.dragEnded)
        }
    }

    // MARK: - Plumbing

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping (Notification) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: handler)))
    }

    private func endSession() {
        isOpen = false
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        loadingTimer?.invalidate()
        loadingTimer = nil
        dragTimer?.invalidate()
        dragTimer = nil
    }

    /// Hiding the panel gives the keyboard back to the app in front. This checks the two
    /// ways that could fail to be true and puts them right or on record.
    private func giveBackTheKeyboard(after panel: NSPanel) {
        if panel.isKeyWindow {
            NSLog("Cutter: the screenshots panel is hidden but still marked as holding the keyboard")
        }
        // Cutter does not make itself active for the panel. If it is active all the same
        // and has no other window to type into, it steps back for the app behind it.
        let hasAnotherWindowToTypeIn = NSApp.windows.contains { $0 !== panel && $0.isVisible && $0.canBecomeKey }
        if NSApp.isActive, !hasAnotherWindowToTypeIn {
            NSApp.hide(nil)
        }
    }

    /// Builds the panel without showing it.
    func makePanel() -> KeyPanel {
        let hostingView = NSHostingView(rootView: ScreenshotBrowserView(model: model, thumbnails: thumbnails))
        let surface = ScreenshotPanelSurface(content: hostingView, contentSize: ScreenshotBrowserView.size)
        // A click in the clear margin around the sheet is a click beside the panel.
        surface.onClickBeside = { [weak self] in
            self?.close(.clickElsewhere)
        }

        // No title bar and no window background: the surface is all there is to see.
        let panel = KeyPanel(
            contentRect: surface.frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = !ScreenshotPanelSurface.drawsItsOwnShadow
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
            self?.close(.command)
        }
        panel.onKeyDown = { [weak self] event in
            guard let self, self.isOpen, let command = ScreenshotBrowserModel.command(for: event) else {
                return false
            }
            self.model.perform(command)
            return true
        }
        panel.contentView = surface
        return panel
    }
}
