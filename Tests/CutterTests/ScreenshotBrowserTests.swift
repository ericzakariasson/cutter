import AppKit
import Testing

@testable import Cutter
import CutterCore

/// What the model did to the world, recorded instead of done.
private final class Recorder {
    var opened: [String] = []
    var copied: [String] = []
    var revealed: [String] = []
    var closes = 0
    var folderReads = 0
    /// Work the model handed to the background, held until the test lets it run.
    var pending: [() -> Void] = []

    func runPending() {
        let work = pending
        pending = []
        work.forEach { $0() }
    }
}

private func screenshots(_ count: Int) -> [Screenshot] {
    (0..<count).map { index in
        Screenshot(
            url: URL(fileURLWithPath: "/samples/Sample \(index).png"),
            date: Date(timeIntervalSinceReferenceDate: TimeInterval(1_000 - index))
        )
    }
}

/// A model that never touches a real folder, the clipboard, Finder or any app.
private func makeModel(
    _ recorder: Recorder,
    deferred: Bool = false,
    find: @escaping () throws -> [Screenshot]
) -> ScreenshotBrowserModel {
    var environment = ScreenshotBrowserModel.Environment()
    environment.location = { (URL(fileURLWithPath: "/samples", isDirectory: true), nil) }
    environment.find = { _, _ in
        recorder.folderReads += 1
        return try find()
    }
    environment.inBackground = { work in
        if deferred {
            recorder.pending.append(work)
        } else {
            work()
        }
    }
    environment.onMain = { $0() }
    environment.open = { recorder.opened.append($0.lastPathComponent) }
    environment.copy = { recorder.copied.append($0.lastPathComponent) }
    environment.reveal = { recorder.revealed.append($0.lastPathComponent) }
    environment.close = { recorder.closes += 1 }
    return ScreenshotBrowserModel(environment: environment)
}

private func keyDown(_ keyCode: UInt16, _ characters: String = "", _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
        characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
    )!
}

@Suite struct ScreenshotBrowserModelTests {
    /// The folder is read when the panel asks, never when the model is created: macOS
    /// must not ask for access to the folder before the panel is first used.
    @Test func nothingIsReadUntilThePanelOpens() {
        let recorder = Recorder()
        let model = makeModel(recorder) { screenshots(3) }
        #expect(recorder.folderReads == 0)
        #expect(model.state == .loading)

        model.reload()
        #expect(recorder.folderReads == 1)
    }

    @Test func listsTheScreenshotsAndSelectsTheNewest() {
        let recorder = Recorder()
        let model = makeModel(recorder) { screenshots(7) }
        model.reload()
        #expect(model.state == .loaded)
        #expect(model.screenshots.count == 7)
        #expect(model.selection == 0)
        #expect(model.folder?.path == "/samples")
    }

    @Test func anEmptyFolderIsSaidToBeEmpty() {
        let recorder = Recorder()
        let model = makeModel(recorder) { [] }
        model.reload()
        #expect(model.state == .empty)
        #expect(model.selection == nil)
    }

    @Test func aRefusalByMacOSIsToldApartFromOtherFailures() {
        let recorder = Recorder()
        let refused = makeModel(recorder) { throw CocoaError(.fileReadNoPermission) }
        refused.reload()
        #expect(refused.state == .notAllowed)

        let posix = makeModel(recorder) { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)) }
        posix.reload()
        #expect(posix.state == .notAllowed)

        let wrapped = makeModel(recorder) {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)),
            ])
        }
        wrapped.reload()
        #expect(wrapped.state == .notAllowed)

        let missing = makeModel(recorder) { throw CocoaError(.fileReadNoSuchFile) }
        missing.reload()
        if case .failed = missing.state {} else {
            Issue.record("a missing folder should be reported as a failure, got \(missing.state)")
        }
    }

    /// While macOS waits for an answer about access, the read has not returned.
    @Test func thePanelShowsLoadingUntilTheFolderHasBeenRead() {
        let recorder = Recorder()
        let model = makeModel(recorder, deferred: true) { screenshots(2) }
        model.reload()
        #expect(model.state == .loading)
        #expect(model.screenshots.isEmpty)

        recorder.runPending()
        #expect(model.state == .loaded)
        #expect(model.screenshots.count == 2)
    }

    @Test func reopeningKeepsTheEarlierListUpUntilTheNewOneArrives() {
        let recorder = Recorder()
        var answer = screenshots(2)
        let model = makeModel(recorder, deferred: true) { answer }
        model.reload()
        recorder.runPending()

        answer = screenshots(5)
        model.reload()
        #expect(model.state == .loaded)
        #expect(model.screenshots.count == 2)

        recorder.runPending()
        #expect(model.screenshots.count == 5)
        #expect(model.selection == 0)
    }

    @Test func onlyTheLatestReadCounts() {
        let recorder = Recorder()
        var answer = screenshots(1)
        let model = makeModel(recorder, deferred: true) { answer }
        model.reload()
        let first = recorder.pending
        recorder.pending = []

        answer = screenshots(4)
        model.reload()
        recorder.runPending()
        #expect(model.screenshots.count == 4)

        // The first read finishes late; its answer is stale by then.
        answer = screenshots(1)
        first.forEach { $0() }
        #expect(model.screenshots.count == 4)
    }

    @Test func reopeningReadsTheFolderAgain() {
        let recorder = Recorder()
        var answer = screenshots(2)
        let model = makeModel(recorder) { answer }
        model.reload()
        model.perform(.move(.right))
        #expect(model.selection == 1)

        answer = screenshots(3)
        model.reload()
        #expect(model.screenshots.count == 3)
        #expect(model.selection == 0)
        #expect(recorder.folderReads == 2)
    }

    @Test func arrowKeysMoveTheSelectionThroughTheGrid() {
        let recorder = Recorder()
        let model = makeModel(recorder) { screenshots(12) }
        model.reload()

        model.perform(.move(.right))
        #expect(model.selection == 1)
        model.perform(.move(.down))
        #expect(model.selection == 1 + ScreenshotBrowserModel.columns)
        model.perform(.move(.last))
        #expect(model.selection == 11)
        model.perform(.move(.first))
        #expect(model.selection == 0)
        #expect(model.selectedScreenshot?.url.lastPathComponent == "Sample 0.png")
    }

    @Test func openCopyAndRevealActOnTheSelectionAndCloseThePanel() {
        let recorder = Recorder()
        let model = makeModel(recorder) { screenshots(5) }
        model.reload()
        model.perform(.move(.right))

        model.perform(.open)
        #expect(recorder.opened == ["Sample 1.png"])
        #expect(recorder.closes == 1)

        model.perform(.copy)
        #expect(recorder.copied == ["Sample 1.png"])
        #expect(recorder.closes == 2)

        model.perform(.reveal)
        #expect(recorder.revealed == ["Sample 1.png"])
        #expect(recorder.closes == 3)
    }

    @Test func aClickedScreenshotIsTheOneActedOn() {
        let recorder = Recorder()
        let model = makeModel(recorder) { screenshots(5) }
        model.reload()

        model.open(model.screenshots[3])
        model.copy(model.screenshots[4])
        model.reveal(model.screenshots[2])
        #expect(recorder.opened == ["Sample 3.png"])
        #expect(recorder.copied == ["Sample 4.png"])
        #expect(recorder.revealed == ["Sample 2.png"])
    }

    @Test func withNothingListedTheKeysDoNothingButClose() {
        let recorder = Recorder()
        let model = makeModel(recorder) { [] }
        model.reload()

        model.perform(.open)
        model.perform(.copy)
        model.perform(.reveal)
        model.perform(.move(.down))
        #expect(recorder.opened.isEmpty && recorder.copied.isEmpty && recorder.revealed.isEmpty)
        #expect(recorder.closes == 0)
        #expect(model.selection == nil)

        model.perform(.close)
        #expect(recorder.closes == 1)
    }
}

@Suite struct ScreenshotPanelKeyTests {
    private func command(_ keyCode: UInt16, _ characters: String = "", _ modifiers: NSEvent.ModifierFlags = []) -> ScreenshotBrowserModel.Command? {
        ScreenshotBrowserModel.command(for: keyDown(keyCode, characters, modifiers))
    }

    @Test func arrowsMove() {
        // The system adds these two flags to every arrow key press.
        let arrow: NSEvent.ModifierFlags = [.function, .numericPad]
        #expect(command(KeyCode.leftArrow, "", arrow) == .move(.left))
        #expect(command(KeyCode.rightArrow, "", arrow) == .move(.right))
        #expect(command(KeyCode.upArrow, "", arrow) == .move(.up))
        #expect(command(KeyCode.downArrow, "", arrow) == .move(.down))
        #expect(command(KeyCode.home, "", [.function]) == .move(.first))
        #expect(command(KeyCode.end, "", [.function]) == .move(.last))
        #expect(command(KeyCode.upArrow, "", arrow.union(.command)) == .move(.first))
        #expect(command(KeyCode.downArrow, "", arrow.union(.command)) == .move(.last))
    }

    @Test func returnOpensAndCommandReturnReveals() {
        #expect(command(KeyCode.returnKey, "\r") == .open)
        #expect(command(KeyCode.keypadEnter, "\u{3}", [.numericPad]) == .open)
        #expect(command(KeyCode.returnKey, "\r", [.command]) == .reveal)
        #expect(command(31, "o", [.command]) == .open)
        #expect(command(15, "r", [.command]) == .reveal)
    }

    @Test func commandCCopies() {
        #expect(command(8, "c", [.command]) == .copy)
        #expect(command(8, "C", [.command, .capsLock]) == .copy)
        // On another keyboard layout the key that types C is elsewhere.
        #expect(command(34, "c", [.command]) == .copy)
    }

    @Test func escapeAndCommandWClose() {
        #expect(command(KeyCode.escape, "\u{1B}") == .close)
        #expect(command(13, "w", [.command]) == .close)
    }

    @Test func otherKeysAreLeftAlone() {
        #expect(command(8, "c") == nil)
        #expect(command(8, "c", [.command, .shift]) == nil)
        #expect(command(8, "c", [.control]) == nil)
        #expect(command(KeyCode.space, " ") == nil)
        #expect(command(KeyCode.tab, "\t") == nil)
        #expect(command(KeyCode.returnKey, "\r", [.option]) == nil)
        // The panel's own shortcut, ⌃⌥S, must reach the global shortcut and close it.
        #expect(command(KeyCode.s, "s", [.control, .option]) == nil)
    }
}

/// The panel is created here but never shown.
@MainActor
@Suite struct ScreenshotPanelTests {
    private func makePanel(holdsKeyboard: Bool?, used: @escaping (NSEvent) -> Bool) -> KeyPanel {
        let panel = KeyPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled], backing: .buffered, defer: true)
        panel.holdsKeyboardOverride = holdsKeyboard
        panel.onKeyDown = used
        return panel
    }

    @Test func thePanelCanTakeTheKeyboardWithoutBeingAMainWindow() {
        let panel = makePanel(holdsKeyboard: nil) { _ in false }
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
    }

    /// A panel that is not on screen must never use a key press or keep it from anyone.
    @Test func aHiddenPanelNeitherUsesNorStopsKeys() {
        var seen = 0
        let panel = makePanel(holdsKeyboard: nil) { _ in
            seen += 1
            return true
        }
        #expect(!panel.isVisible)
        #expect(!panel.holdsKeyboard)
        #expect(!panel.performKeyEquivalent(with: keyDown(12, "q", [.command])))
        #expect(!panel.performKeyEquivalent(with: keyDown(8, "c", [.command])))
        panel.sendEvent(keyDown(KeyCode.returnKey, "\r"))
        #expect(seen == 0)
    }

    /// ⌘Q pressed over the open panel is meant for the app behind it. It must not reach
    /// Cutter's own menu, where it would quit Cutter.
    @Test func whileOpenCommandKeysThePanelDoesNotUseGoNoFurther() {
        var seen: [UInt16] = []
        let panel = makePanel(holdsKeyboard: true) { event in
            seen.append(event.keyCode)
            return false
        }
        #expect(panel.performKeyEquivalent(with: keyDown(12, "q", [.command])))
        #expect(panel.performKeyEquivalent(with: keyDown(43, ",", [.command])))
        #expect(seen == [12, 43])
    }

    @Test func whileOpenThePanelsOwnCommandKeysReachIt() {
        var commands: [ScreenshotBrowserModel.Command] = []
        let panel = makePanel(holdsKeyboard: true) { event in
            guard let command = ScreenshotBrowserModel.command(for: event) else {
                return false
            }
            commands.append(command)
            return true
        }
        #expect(panel.performKeyEquivalent(with: keyDown(8, "c", [.command])))
        #expect(panel.performKeyEquivalent(with: keyDown(KeyCode.returnKey, "\r", [.command])))
        #expect(commands == [.copy, .reveal])
    }

    @Test func escapeWithNoTakerClosesThePanel() {
        var cancels = 0
        let panel = makePanel(holdsKeyboard: true) { _ in false }
        panel.onCancel = { cancels += 1 }
        panel.cancelOperation(nil)
        #expect(cancels == 1)
    }
}

/// The panel holds the keyboard while it is open, so it must let go at the first sign
/// that the user is elsewhere. These tests run the controller's rules without ever
/// putting the panel on screen and without listening to this Mac's real clicks.
@MainActor
@Suite struct ScreenshotPanelLetsGoTests {
    private final class Session {
        let controller = ScreenshotPanelController()
        var reasons: [ScreenshotPanelController.CloseReason] = []
        var mouseButtonDown = true
        var answer: [Screenshot] = screenshots(6)
        /// Folder reads the model has asked for and that have not answered yet.
        var pendingReads: [() -> Void] = []
        var holdReads = false

        init() {
            controller.listensToTheSystem = false
            controller.onClose = { [unowned self] in reasons.append($0) }
            controller.isMouseButtonDown = { [unowned self] in mouseButtonDown }
            // Nothing real is read, opened, copied or revealed.
            controller.model.environment.location = { (URL(fileURLWithPath: "/samples", isDirectory: true), nil) }
            controller.model.environment.find = { [unowned self] _, _ in answer }
            controller.model.environment.inBackground = { [unowned self] work in
                if holdReads {
                    pendingReads.append(work)
                } else {
                    work()
                }
            }
            controller.model.environment.onMain = { $0() }
            controller.model.environment.open = { _ in }
            controller.model.environment.copy = { _ in }
            controller.model.environment.reveal = { _ in }
        }

        /// The panel as it is right after opening, with the folder read or still being read.
        func open(loaded: Bool = true) {
            holdReads = !loaded
            controller.model.reload()
            controller.beginSession()
        }
    }

    @Test func nothingIsReadAndNothingIsOpenUntilAskedToShow() {
        let controller = ScreenshotPanelController()
        #expect(!controller.isOpen)
        #expect(controller.model.state == .loading)
        #expect(controller.model.screenshots.isEmpty)
        #expect(controller.model.folder == nil)
    }

    @Test func losingTheKeyboardClosesThePanel() {
        let session = Session()
        session.open()
        session.controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        #expect(session.reasons == [.lostKeyboard])
        #expect(!session.controller.isOpen)
    }

    /// While the folder is being read, macOS may be asking whether Cutter may read it.
    /// The panel must not hold on through that: it closes like at any other time.
    @Test func losingTheKeyboardClosesThePanelEvenWhileItIsLoading() {
        let session = Session()
        session.open(loaded: false)
        #expect(session.controller.model.state == .loading)
        session.controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        #expect(session.reasons == [.lostKeyboard])
    }

    @Test func aClickElsewhereClosesThePanelEvenWhileItIsLoading() {
        let session = Session()
        session.open(loaded: false)
        session.controller.close(.clickElsewhere)
        #expect(session.reasons == [.clickElsewhere])
        #expect(!session.controller.isOpen)
    }

    @Test func anotherAppComingForwardClosesThePanel() {
        let session = Session()
        session.open()
        // Cutter itself coming forward, for its settings window, is not a reason.
        session.controller.appCameForward(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        #expect(session.reasons.isEmpty)

        session.controller.appCameForward(processIdentifier: 1)
        #expect(session.reasons == [.otherAppCameForward])
    }

    @Test func aReadThatTakesTooLongClosesThePanel() {
        let session = Session()
        session.open(loaded: false)
        session.controller.loadingPatienceRanOut()
        #expect(session.reasons == [.slowLoading])
    }

    @Test func patienceRunningOutDoesNothingOnceTheFolderHasBeenRead() {
        let session = Session()
        session.open()
        #expect(session.controller.model.state == .loaded)
        session.controller.loadingPatienceRanOut()
        #expect(session.reasons.isEmpty)
        #expect(session.controller.isOpen)
    }

    /// After a drag out there is no click elsewhere, and the user's next move is in the
    /// app the screenshot went to. The panel must not sit there holding the keyboard.
    @Test func thePanelClosesWhenADragOutOfItEnds() {
        let session = Session()
        session.open()
        session.mouseButtonDown = true
        session.controller.model.dragBegan(at: 2)
        #expect(session.controller.model.selection == 2)

        session.controller.checkWhetherDragEnded()
        #expect(session.reasons.isEmpty)

        session.mouseButtonDown = false
        session.controller.checkWhetherDragEnded()
        #expect(session.reasons == [.dragEnded])
        #expect(!session.controller.isOpen)
    }

    @Test func withoutADragTheMouseButtonMeansNothing() {
        let session = Session()
        session.open()
        session.mouseButtonDown = false
        session.controller.checkWhetherDragEnded()
        #expect(session.reasons.isEmpty)
    }

    @Test func escapeAndTheThreeActionsCloseThePanel() {
        for command in [ScreenshotBrowserModel.Command.close, .open, .copy, .reveal] {
            let session = Session()
            session.open()
            session.controller.model.perform(command)
            #expect(session.reasons == [.command])
            #expect(!session.controller.isOpen)
        }
    }

    @Test func theShortcutClosesAnOpenPanel() {
        let session = Session()
        session.open()
        session.controller.toggle()
        #expect(session.reasons == [.toggledOff])
    }

    @Test func closingTwiceClosesOnce() {
        let session = Session()
        session.open()
        session.controller.close(.clickElsewhere)
        session.controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        session.controller.close(.command)
        session.controller.checkWhetherDragEnded()
        session.controller.loadingPatienceRanOut()
        #expect(session.reasons == [.clickElsewhere])
    }

    /// The folder's answer arriving after the panel has closed must not bring it back.
    @Test func aLateAnswerDoesNotReopenAClosedPanel() {
        let session = Session()
        session.open(loaded: false)
        session.controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))

        session.pendingReads.forEach { $0() }
        #expect(session.controller.model.state == .loaded)
        #expect(!session.controller.isOpen)
        #expect(session.reasons == [.lostKeyboard])
    }
}

@Suite struct ScreenshotClipboardTests {
    /// A pasteboard of the test's own; the real clipboard is never touched.
    private func pasteboard() -> NSPasteboard {
        NSPasteboard.withUniqueName()
    }

    private func samplePNG(in folder: URL, named name: String) throws -> URL {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 6, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let file = folder.appendingPathComponent(name)
        try #require(bitmap.representation(using: name.hasSuffix("png") ? .png : .jpeg, properties: [:])).write(to: file)
        return file
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CutterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func aScreenshotIsCopiedAsAFileAndAsAPicture() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try samplePNG(in: folder, named: "Sample.png")
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }

        ScreenshotClipboard.copy(file, to: pasteboard)

        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(urls?.map(\.lastPathComponent) == ["Sample.png"])
        #expect(pasteboard.data(forType: .png) == (try Data(contentsOf: file)))
        let image = try #require(NSImage(pasteboard: pasteboard))
        #expect(image.representations.first?.pixelsWide == 8)
    }

    @Test func anotherFormatIsCopiedAsAPictureToo() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try samplePNG(in: folder, named: "Sample.jpg")
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }

        ScreenshotClipboard.copy(file, to: pasteboard)
        #expect(pasteboard.data(forType: .tiff) != nil)
        #expect(pasteboard.string(forType: .fileURL) == file.absoluteString)
    }

    @Test func copyingReplacesWhatWasThere() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try samplePNG(in: folder, named: "Sample.png")
        let pasteboard = pasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("earlier text", forType: .string)

        ScreenshotClipboard.copy(file, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(pasteboard.pasteboardItems?.count == 1)
    }
}

@Suite struct ThumbnailTests {
    @Test func aThumbnailIsNoLargerThanACellNeeds() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CutterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 900, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let file = folder.appendingPathComponent("Sample.png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: file)

        let store = ThumbnailStore()
        let screenshot = Screenshot(url: file, date: Date(timeIntervalSinceReferenceDate: 5))
        #expect(store.cached(screenshot) == nil)
        let thumbnail = try #require(store.load(screenshot))
        #expect(Int(thumbnail.size.width) == ThumbnailStore.pixelSize)
        #expect(Int(thumbnail.size.height) == ThumbnailStore.pixelSize * 900 / 1600)
        #expect(store.cached(screenshot) === thumbnail)
    }

    @Test func aFileThatIsNotAPictureHasNoThumbnail() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("CutterTests-\(UUID().uuidString).png")
        try Data("not a picture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(ThumbnailStore().load(Screenshot(url: file, date: Date())) == nil)
    }
}
