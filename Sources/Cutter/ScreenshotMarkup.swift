import AppKit
import CutterCore
import ImageIO
import UniformTypeIdentifiers

/// Opens a screenshot in macOS's own Markup editor, the one the system uses for the
/// screenshot thumbnail, Quick Look and Mail: draw, shapes, arrows, text, crop. When the
/// editing is done, the edited picture replaces the file.
///
/// Markup is an editing extension that works on a picture shown in a window of the app
/// that asks for it. So this shows the screenshot in a window of Cutter's and hands that
/// to Markup. The window also offers Markup again and Preview, in case the editor does
/// not come up.
///
/// The editor is never opened by a test: it would take the keyboard. What is tested is
/// what happens to the file with what the editor returns.
final class ScreenshotMarkupController: NSObject, NSSharingServiceDelegate, NSWindowDelegate {
    static let serviceName = NSSharingService.Name("com.apple.MarkupUI.Markup")

    /// Called with the file after an edited picture has replaced it.
    var onSaved: ((URL) -> Void)?

    private var window: NSWindow?
    private var imageView: NSImageView?
    private var file: URL?
    private var service: NSSharingService?

    static var isAvailable: Bool {
        NSSharingService(named: serviceName) != nil
    }

    /// Shows the picture and starts Markup on it.
    func edit(_ file: URL) {
        closeWindow()
        guard let image = NSImage(contentsOf: file) else {
            NSLog("Cutter: markup: the picture could not be read; opening it in its app instead")
            NSWorkspace.shared.open(file)
            return
        }
        self.file = file

        let window = makeWindow(for: image)
        self.window = window
        // Markup needs the keyboard and a frontmost window, so here Cutter does come forward.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSLog("Cutter: markup: window opened")

        // Started on the next turn of the run loop, when the window is really on screen
        // and Markup can be told where the picture is.
        DispatchQueue.main.async { [weak self] in
            self?.startMarkup()
        }
    }

    @objc private func startMarkup() {
        guard let file, window != nil else {
            return
        }
        guard let service = NSSharingService(named: Self.serviceName),
              let provider = NSItemProvider(contentsOf: file)
        else {
            NSLog("Cutter: markup: the Markup editor is not available on this Mac")
            return
        }
        service.delegate = self
        self.service = service
        // The editor is asked whatever it answers here; the answer is for the log.
        NSLog(
            "Cutter: markup: editor asked for (says it can: %@, Cutter in front: %@, window has the keyboard: %@)",
            service.canPerform(withItems: [provider]) ? "yes" : "no",
            NSApp.isActive ? "yes" : "no",
            window?.isKeyWindow == true ? "yes" : "no"
        )
        service.perform(withItems: [provider])
    }

    @objc private func openInPreview() {
        guard let file else {
            return
        }
        NSWorkspace.shared.open(file)
        closeWindow()
    }

    @objc private func closeFromButton() {
        closeWindow()
    }

    // MARK: - What Markup asks and tells

    func sharingService(
        _ sharingService: NSSharingService,
        sourceWindowForShareItems items: [Any],
        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>
    ) -> NSWindow? {
        sharingContentScope.pointee = .item
        return window
    }

    func sharingService(_ sharingService: NSSharingService, sourceFrameOnScreenForShareItem item: Any) -> NSRect {
        guard let imageView, let window = imageView.window else {
            return .zero
        }
        return window.convertToScreen(imageView.convert(pictureFrame(in: imageView), to: nil))
    }

    func sharingService(
        _ sharingService: NSSharingService,
        transitionImageForShareItem item: Any,
        contentRect: UnsafeMutablePointer<NSRect>
    ) -> NSImage? {
        imageView?.image
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        // What comes back is logged by kind only, never by name or content.
        NSLog("Cutter: markup: editor returned %ld item(s): %@", items.count, items.map { String(describing: type(of: $0)) }.joined(separator: ", "))
        guard let file else {
            return
        }
        EditedPicture.load(from: items) { [weak self] picture in
            DispatchQueue.main.async {
                self?.save(picture, to: file)
            }
        }
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSUserCancelledError {
            NSLog("Cutter: markup: cancelled; the file is unchanged")
            closeWindow()
        } else {
            // The window stays, with its buttons, so the picture can still be edited.
            NSLog("Cutter: markup: the editor failed (%@ %ld)", error.domain, error.code)
        }
    }

    private func save(_ picture: EditedPicture?, to file: URL) {
        guard let picture else {
            NSLog("Cutter: markup: nothing usable came back; the file is unchanged")
            return
        }
        do {
            try ScreenshotFile.replace(file, with: picture)
            NSLog("Cutter: markup: saved over the original (%@)", picture.typeIdentifier)
            onSaved?(file)
            closeWindow()
        } catch {
            NSLog("Cutter: markup: could not save: %@", (error as NSError).domain)
            imageView?.image = NSImage(contentsOf: file)
        }
    }

    // MARK: - The window

    func windowWillClose(_ notification: Notification) {
        window = nil
        imageView = nil
        file = nil
        service = nil
        // Cutter came forward for the editor. With nothing left to show, it steps back
        // for the app that was in front before.
        DispatchQueue.main.async {
            let hasAWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
            if NSApp.isActive, !hasAWindow {
                NSApp.hide(nil)
            }
        }
    }

    private func closeWindow() {
        window?.close()
    }

    /// The picture's own rectangle inside the image view, which fits it proportionally.
    private func pictureFrame(in view: NSImageView) -> NSRect {
        guard let size = view.image?.size, size.width > 0, size.height > 0 else {
            return view.bounds
        }
        let scale = min(view.bounds.width / size.width, view.bounds.height / size.height, 1)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(
            x: view.bounds.midX - fitted.width / 2,
            y: view.bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// Builds the window without showing it.
    func makeWindow(for image: NSImage) -> NSWindow {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let pictureSize = Self.windowPictureSize(for: image.size, in: visible.size)

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        // The picture takes whatever room the window has; the buttons keep their size.
        for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            imageView.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: axis)
            imageView.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: axis)
        }
        self.imageView = imageView

        let markup = NSButton(title: "Markup", target: self, action: #selector(startMarkup))
        let preview = NSButton(title: "Open in Preview", target: self, action: #selector(openInPreview))
        // No key of its own: Return and Escape belong to the editor while it is up, and
        // must not close the window under it.
        let close = NSButton(title: "Close", target: self, action: #selector(closeFromButton))
        let gap = NSView()
        gap.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let buttons = NSStackView(views: [markup, preview, gap, close])
        buttons.orientation = .horizontal
        buttons.distribution = .fill
        buttons.setContentHuggingPriority(.required, for: .vertical)
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(imageView)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            imageView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 14),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: pictureSize.width + 32, height: pictureSize.height + 76),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Markup"
        window.contentView = content
        window.contentMinSize = NSSize(width: 420, height: 300)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    /// The size the picture is shown at: its own size, or smaller to leave room on the
    /// screen, and never tiny.
    static func windowPictureSize(for picture: NSSize, in screen: NSSize) -> NSSize {
        guard picture.width > 0, picture.height > 0 else {
            return NSSize(width: 480, height: 320)
        }
        let limit = NSSize(width: screen.width * 0.8 - 32, height: screen.height * 0.8 - 76)
        let scale = min(limit.width / picture.width, limit.height / picture.height, 1)
        return NSSize(
            width: max((picture.width * scale).rounded(), 388),
            height: max((picture.height * scale).rounded(), 224)
        )
    }
}

/// A picture as an editor hands it back: its bytes and what format they are in.
struct EditedPicture: Equatable {
    var data: Data
    var typeIdentifier: String

    /// Finds the picture in what Markup returned. The form is not documented, so every
    /// reasonable one is accepted: an item provider, an extension item holding one, a
    /// file, an image, or raw data.
    static func load(from items: [Any], completion: @escaping (EditedPicture?) -> Void) {
        for item in items {
            if let extensionItem = item as? NSExtensionItem, let providers = extensionItem.attachments, !providers.isEmpty {
                load(from: providers, completion: completion)
                return
            }
            if let provider = item as? NSItemProvider {
                // Kinds of data only; nothing here names the file.
                NSLog("Cutter: markup: the returned item offers %@", provider.registeredTypeIdentifiers.joined(separator: ", "))
                let types = provider.registeredTypeIdentifiers
                if let type = types.first(where: { UTType($0)?.conforms(to: .image) == true || UTType($0)?.conforms(to: .pdf) == true }) {
                    provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                        completion(data.map { EditedPicture(data: $0, typeIdentifier: type) })
                    }
                    return
                }
                if let type = types.first(where: { UTType($0)?.conforms(to: .fileURL) == true }) {
                    // A file of the editor's own; its contents are read while it is lent.
                    provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                        guard let data, let url = URL(dataRepresentation: data, relativeTo: nil), let contents = try? Data(contentsOf: url) else {
                            completion(nil)
                            return
                        }
                        completion(EditedPicture(data: contents, typeIdentifier: UTType.image.identifier))
                    }
                    return
                }
                continue
            }
            if let url = item as? URL, let data = try? Data(contentsOf: url) {
                let type = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.png.identifier
                completion(EditedPicture(data: data, typeIdentifier: type))
                return
            }
            if let image = item as? NSImage, let tiff = image.tiffRepresentation {
                completion(EditedPicture(data: tiff, typeIdentifier: UTType.tiff.identifier))
                return
            }
            if let data = item as? Data {
                completion(EditedPicture(data: data, typeIdentifier: UTType.image.identifier))
                return
            }
        }
        completion(nil)
    }
}

/// Puts an edited picture in place of a screenshot file.
enum ScreenshotFile {
    enum Failure: Error {
        case notAPicture
        case cannotConvert
    }

    /// Replaces the file's contents and keeps what makes it the same screenshot: its
    /// name, its format, the time it was taken, and the mark macOS put on it. The new
    /// contents are written beside the file first, so a failure leaves the original whole.
    static func replace(_ file: URL, with picture: EditedPicture, fileManager: FileManager = .default) throws {
        let data = try contents(of: picture, inTheFormatOf: file)
        let wasMarked = ScreenshotFinder.isMarkedAsScreenCapture(file)
        let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate

        let temporary = file.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).\(file.pathExtension)")
        try data.write(to: temporary)
        do {
            _ = try fileManager.replaceItemAt(file, withItemAt: temporary)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        if wasMarked {
            try? ScreenshotFinder.markAsScreenCapture(file)
        }
        if let created {
            try? fileManager.setAttributes([.creationDate: created], ofItemAtPath: file.path)
        }
    }

    /// The picture's bytes in the format the file's extension names, converted if the
    /// editor returned another format.
    static func contents(of picture: EditedPicture, inTheFormatOf file: URL) throws -> Data {
        guard let wanted = UTType(filenameExtension: file.pathExtension) else {
            throw Failure.notAPicture
        }
        if let got = UTType(picture.typeIdentifier), got.conforms(to: wanted) || wanted.conforms(to: got), got != .image {
            return picture.data
        }
        guard let source = CGImageSourceCreateWithData(picture.data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else {
            throw Failure.notAPicture
        }
        // The file already holds exactly this format: keep the bytes as they are.
        if let sourceType = CGImageSourceGetType(source) as String?, UTType(sourceType) == wanted {
            return picture.data
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, wanted.identifier as CFString, 1, nil) else {
            throw Failure.cannotConvert
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.cannotConvert
        }
        return output as Data
    }
}
