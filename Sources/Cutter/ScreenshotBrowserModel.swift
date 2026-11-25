import AppKit
import CutterCore

/// The state behind the recent-screenshots panel: what is listed, what is selected, and
/// what the keys do.
///
/// The screenshot folder is read only in `reload()`, which the panel calls when it opens.
/// Nothing here runs at launch, so macOS asks for access to the folder the first time the
/// panel is used and not before.
final class ScreenshotBrowserModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded
        case empty
        /// macOS did not let Cutter read the folder.
        case notAllowed
        case failed(String)
    }

    enum Command: Equatable {
        case move(GridSelection.Move)
        case open
        case copy
        case reveal
        case close
    }

    /// Everything the model does to the world, replaceable in tests.
    struct Environment {
        /// The screenshot folder and file-name prefix macOS is set to.
        var location: () -> (folder: URL, namePrefix: String?) = { ScreenshotLocation.current() }
        var find: (URL, String?) throws -> [Screenshot] = { folder, namePrefix in
            try ScreenshotFinder.recent(in: folder, namePrefix: namePrefix, limit: ScreenshotBrowserModel.limit)
        }
        /// Reading the folder waits for the user's answer when macOS asks for access, so
        /// it must not happen on the main thread.
        var inBackground: (@escaping () -> Void) -> Void = { DispatchQueue.global(qos: .userInitiated).async(execute: $0) }
        var onMain: (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }
        var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
        var copy: (URL) -> Void = { ScreenshotClipboard.copy($0) }
        var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        var close: () -> Void = {}
        /// A screenshot is being dragged out of the panel.
        var dragBegan: () -> Void = {}
    }

    /// How many screenshots the panel lists.
    static let limit = 30
    static let columns = 5

    @Published private(set) var state: State = .loading
    @Published private(set) var screenshots: [Screenshot] = []
    @Published private(set) var folder: URL?
    @Published var selection: Int?

    var environment: Environment
    private var generation = 0

    init(environment: Environment = Environment()) {
        self.environment = environment
    }

    var selectedScreenshot: Screenshot? {
        selection.flatMap { screenshots.indices.contains($0) ? screenshots[$0] : nil }
    }

    /// Reads the folder again. The newest screenshot is selected when the list arrives.
    /// A list from an earlier look stays up meanwhile, so that reopening the panel does
    /// not flash empty.
    func reload() {
        generation += 1
        let request = generation
        if screenshots.isEmpty {
            state = .loading
        }
        let environment = self.environment

        environment.inBackground { [weak self] in
            let location = environment.location()
            let result = Result { try environment.find(location.folder, location.namePrefix) }
            environment.onMain {
                // A newer request has been made since; its answer is the one that counts.
                guard let self, request == self.generation else {
                    return
                }
                self.folder = location.folder
                switch result {
                case .success(let screenshots):
                    self.screenshots = screenshots
                    self.selection = screenshots.isEmpty ? nil : 0
                    self.state = screenshots.isEmpty ? .empty : .loaded
                case .failure(let error):
                    self.screenshots = []
                    self.selection = nil
                    self.state = Self.isPermissionError(error) ? .notAllowed : .failed(error.localizedDescription)
                }
            }
        }
    }

    func perform(_ command: Command) {
        switch command {
        case .move(let move):
            selection = GridSelection.index(after: move, from: selection, count: screenshots.count, columns: Self.columns)
        case .open:
            act(on: selectedScreenshot, environment.open)
        case .copy:
            act(on: selectedScreenshot, environment.copy)
        case .reveal:
            act(on: selectedScreenshot, environment.reveal)
        case .close:
            environment.close()
        }
    }

    /// Opens, copies or reveals one screenshot and closes the panel: the job is done, and
    /// the app the user came from gets the keyboard back.
    func open(_ screenshot: Screenshot) {
        act(on: screenshot, environment.open)
    }

    func copy(_ screenshot: Screenshot) {
        act(on: screenshot, environment.copy)
    }

    func reveal(_ screenshot: Screenshot) {
        act(on: screenshot, environment.reveal)
    }

    /// The screenshot at this index is being dragged out. It becomes the selection, and
    /// the panel is told, so that it can close when the drag is over.
    func dragBegan(at index: Int) {
        if screenshots.indices.contains(index) {
            selection = index
        }
        environment.dragBegan()
    }

    private func act(on screenshot: Screenshot?, _ action: (URL) -> Void) {
        guard let screenshot else {
            return
        }
        action(screenshot.url)
        environment.close()
    }

    /// What a key press in the panel means, or nil when the panel has no use for it.
    static func command(for event: NSEvent) -> Command? {
        guard event.type == .keyDown else {
            return nil
        }
        let modifiers = KeyCombo.Modifiers(event.modifierFlags)
        let character = event.charactersIgnoringModifiers?.lowercased()

        switch (modifiers, event.keyCode) {
        case ([], KeyCode.leftArrow): return .move(.left)
        case ([], KeyCode.rightArrow): return .move(.right)
        case ([], KeyCode.upArrow): return .move(.up)
        case ([], KeyCode.downArrow): return .move(.down)
        case ([], KeyCode.home), ([.command], KeyCode.upArrow): return .move(.first)
        case ([], KeyCode.end), ([.command], KeyCode.downArrow): return .move(.last)
        case ([], KeyCode.returnKey), ([], KeyCode.keypadEnter): return .open
        case ([.command], KeyCode.returnKey), ([.command], KeyCode.keypadEnter): return .reveal
        case ([], KeyCode.escape): return .close
        default: break
        }
        guard modifiers == [.command] else {
            return nil
        }
        switch character {
        case "c": return .copy
        case "r": return .reveal
        case "o": return .open
        case "w": return .close
        default: return nil
        }
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError {
            return true
        }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EPERM) || error.code == Int(EACCES) {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
            return isPermissionError(underlying)
        }
        return false
    }
}

/// Puts a screenshot on the clipboard both as a file and as a picture, so it pastes into
/// Finder and mail as a file and into chats, documents and image editors as an image.
enum ScreenshotClipboard {
    static func copy(_ url: URL, to pasteboard: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let data = try? Data(contentsOf: url) {
            if url.pathExtension.lowercased() == "png" {
                item.setData(data, forType: .png)
            } else if let tiff = NSImage(data: data)?.tiffRepresentation {
                item.setData(tiff, forType: .tiff)
            }
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
