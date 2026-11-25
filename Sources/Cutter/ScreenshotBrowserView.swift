import AppKit
import CutterCore
import ImageIO
import QuickLookThumbnailing
import SwiftUI

/// Small versions of the screenshots, made off the main thread and kept while the panel
/// is in use.
final class ThumbnailStore {
    private let cache = NSCache<NSString, NSImage>()

    /// Longest side in pixels: twice the cell's width, for Retina screens.
    static let pixelSize = 2 * Int(ScreenshotBrowserView.cellWidth)

    func cached(_ screenshot: Screenshot) -> NSImage? {
        cache.object(forKey: key(screenshot))
    }

    /// Reads the file and scales it down. Safe to call from any thread.
    func load(_ screenshot: Screenshot) -> NSImage? {
        if let image = cached(screenshot) {
            return image
        }
        guard let image = Self.thumbnail(of: screenshot.url) else {
            return nil
        }
        cache.setObject(image, forKey: key(screenshot))
        return image
    }

    /// Drops everything kept, after a file's contents have changed. The thumbnails are
    /// made again the next time the panel shows them.
    func forgetEverything() {
        cache.removeAllObjects()
    }

    private func key(_ screenshot: Screenshot) -> NSString {
        "\(screenshot.url.path)|\(screenshot.date.timeIntervalSinceReferenceDate)" as NSString
    }

    static func thumbnail(of url: URL) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
        ]
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        if ScreenshotFinder.recordingExtensions.contains(url.pathExtension.lowercased()) {
            return movieThumbnail(of: url)
        }
        // ImageIO does not read PDFs, which the screenshot tool can be set to write.
        return NSImage(contentsOf: url)
    }

    /// A frame of a recording, from the system's own thumbnail service. It answers on
    /// another thread; this waits for it, so call it off the main thread.
    private static func movieThumbnail(of url: URL) -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: pixelSize, height: pixelSize),
            scale: 1,
            representationTypes: .thumbnail
        )
        let done = DispatchSemaphore(value: 0)
        var image: NSImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            image = representation?.nsImage
            done.signal()
        }
        _ = done.wait(timeout: .now() + 5)
        return image
    }
}

/// The contents of the recent-screenshots panel. The panel's surface, glass or blur, is
/// `ScreenshotPanelSurface`; this view draws only what sits on it.
struct ScreenshotBrowserView: View {
    @ObservedObject var model: ScreenshotBrowserModel
    let thumbnails: ThumbnailStore
    /// A plain background for drawing the view off-screen, where the panel's surface is
    /// not available.
    var opaqueBackground = false

    static let cellWidth: CGFloat = 168
    static let cellHeight: CGFloat = 112
    private static let spacing: CGFloat = 12
    private static let padding: CGFloat = 22
    static let size = CGSize(
        width: CGFloat(ScreenshotBrowserModel.columns) * cellWidth
            + CGFloat(ScreenshotBrowserModel.columns - 1) * spacing + 2 * padding,
        height: 580
    )

    var body: some View {
        layout
            .frame(width: Self.size.width, height: Self.size.height)
            .background(opaqueBackground ? Color(nsColor: .windowBackgroundColor) : Color.clear)
    }

    /// Header, list and footer stacked, with the system's separator lines between them.
    ///
    /// macOS 26 can instead let the list scroll beneath the bars and soften it there
    /// (`safeAreaBar` with a scroll edge effect). That is left out on purpose: drawn
    /// off-screen, which is the only way this panel can be checked before it ships, the
    /// list came out empty with it.
    private var layout: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Recent Screenshots")
                .font(.headline)
            Spacer()
            if let folder = model.folder {
                Label(folder.lastPathComponent, systemImage: "folder")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help(folder.path)
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .loaded:
            grid
        case .empty:
            UnavailableMessage(
                symbol: "photo.on.rectangle.angled",
                title: "No Screenshots Yet",
                detail: "macOS saves screenshots and screen recordings to \(model.folder?.lastPathComponent ?? "the Desktop"). Take one with ⇧⌘3, ⇧⌘4 or ⇧⌘5 and it shows up here."
            )
        case .notAllowed:
            UnavailableMessage(
                symbol: "lock",
                title: "Cutter May Not Read \(model.folder?.lastPathComponent ?? "the Folder")",
                detail: "Allow it under System Settings > Privacy & Security > Files and Folders > Cutter, then open this panel again.",
                actionTitle: "Open Privacy & Security…"
            ) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                    NSWorkspace.shared.open(url)
                }
                model.perform(.close)
            }
        case .failed(let reason):
            UnavailableMessage(symbol: "exclamationmark.triangle", title: "Could Not Read the Screenshots", detail: reason)
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(Self.cellWidth), spacing: Self.spacing),
                        count: ScreenshotBrowserModel.columns
                    ),
                    spacing: 10
                ) {
                    // Each cell is known by its file, in the list and to the scroll view
                    // alike. Known by its place in the list instead, a cell stayed as it
                    // was when the list changed: the grid drew the old pictures while
                    // the keyboard acted on the new list.
                    ForEach(Array(model.screenshots.enumerated()), id: \.element.url) { index, screenshot in
                        ScreenshotCell(
                            screenshot: screenshot,
                            isSelected: model.selection == index,
                            thumbnails: thumbnails,
                            version: model.picturesVersion
                        )
                        .id(screenshot.url)
                        .onTapGesture(count: 2) {
                            model.edit(screenshot)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            model.selection = index
                        })
                        .onDrag {
                            model.dragBegan(at: index)
                            return NSItemProvider(contentsOf: screenshot.url) ?? NSItemProvider()
                        }
                        .contextMenu {
                            if !screenshot.isRecording {
                                Button("Markup") { model.edit(screenshot) }
                            }
                            Button("Open") { model.open(screenshot) }
                            Button("Copy") { model.copy(screenshot) }
                            Button("Show in Finder") { model.reveal(screenshot) }
                        }
                    }
                }
                .padding(.horizontal, Self.padding)
                .padding(.vertical, 8)
            }
            .onChange(of: model.selectedScreenshot?.url) { selected in
                if let selected {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(selected)
                    }
                }
            }
        }
    }

    /// The three things to do with the selected screenshot, as ordinary buttons with
    /// their keys beside the titles.
    private var footer: some View {
        HStack(spacing: 8) {
            actionButton("Markup", keys: "⌘E", help: "Draw on it or crop it") { model.perform(.edit) }
                .disabled(model.selectedScreenshot?.isRecording ?? true)
            actionButton("Open", keys: "↩", help: "Open in the default app") { model.perform(.open) }
            actionButton("Copy", keys: "⌘C", help: "Copy to the clipboard") { model.perform(.copy) }
            actionButton("Show in Finder", keys: "⌘↩", help: "Show the file in Finder") { model.perform(.reveal) }
            Spacer()
            if model.state == .loaded {
                Text(Self.countLabel(model.screenshots.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    static func countLabel(_ count: Int) -> String {
        if count >= ScreenshotBrowserModel.limit {
            return "Newest \(ScreenshotBrowserModel.limit)"
        }
        return count == 1 ? "1 item" : "\(count) items"
    }

    private func actionButton(_ title: String, keys: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text(keys)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        // The panel's keys act on the selection; the buttons are for the mouse.
        .focusable(false)
        .disabled(model.selectedScreenshot == nil)
        .help(help)
    }
}

/// The system's own look for "nothing to show" where it exists (macOS 14 and later).
private struct UnavailableMessage: View {
    let symbol: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(detail)
            } actions: {
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .padding(.top, 4)
                }
            }
        }
    }
}

/// One screenshot: the picture, and under it when it was taken.
///
/// Selection looks as it does in Finder's icon view: a quiet fill behind the picture and
/// the label on the system's selection colour, which follows the accent colour chosen in
/// System Settings.
private struct ScreenshotCell: View {
    let screenshot: Screenshot
    let isSelected: Bool
    let thumbnails: ThumbnailStore
    /// Changes when a file has been edited; the picture is then read again.
    let version: Int

    @State private var image: NSImage?
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)
                    .opacity(isSelected ? 1 : (isHovered ? 0.5 : 0))
                if let image = thumbnails.cached(screenshot) ?? image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(.separator, lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        .padding(9)
                }
                if screenshot.isRecording {
                    // The usual sign for something that plays.
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                }
            }
            .frame(width: ScreenshotBrowserView.cellWidth, height: ScreenshotBrowserView.cellHeight)

            Text(Self.caption(for: screenshot.date))
                .font(.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : Color.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(nsColor: .selectedContentBackgroundColor))
                        .opacity(isSelected ? 1 : 0)
                )
        }
        .frame(width: ScreenshotBrowserView.cellWidth)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onAppear {
            if image == nil {
                loadThumbnail()
            }
        }
        .onChange(of: version) { _ in
            loadThumbnail()
        }
        .onChange(of: screenshot) { _ in
            // The same file with another date is another picture.
            loadThumbnail()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(screenshot.isRecording ? "Screen recording" : "Screenshot"), \(Self.caption(for: screenshot.date))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Reading and scaling a full-size screenshot takes a moment, so it happens off the
    /// main thread; the cell shows nothing until then.
    private func loadThumbnail() {
        let store = thumbnails
        let screenshot = self.screenshot
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = store.load(screenshot)
            DispatchQueue.main.async {
                image = loaded
            }
        }
    }

    /// "Today at 9:12 AM", "Yesterday at 5:40 PM", then the date.
    static func caption(for date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
