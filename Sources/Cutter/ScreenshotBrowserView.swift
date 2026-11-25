import AppKit
import CutterCore
import ImageIO
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
        // ImageIO does not read PDFs, which the screenshot tool can be set to write.
        return NSImage(contentsOf: url)
    }
}

/// The contents of the recent-screenshots panel.
struct ScreenshotBrowserView: View {
    @ObservedObject var model: ScreenshotBrowserModel
    let thumbnails: ThumbnailStore
    /// A plain background for drawing the view off-screen, where the panel's blur is not
    /// available.
    var opaqueBackground = false

    static let cellWidth: CGFloat = 168
    static let cellHeight: CGFloat = 112
    private static let spacing: CGFloat = 12
    private static let padding: CGFloat = 20
    static let size = CGSize(
        width: CGFloat(ScreenshotBrowserModel.columns) * cellWidth
            + CGFloat(ScreenshotBrowserModel.columns - 1) * spacing + 2 * padding,
        height: 560
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(background)
    }

    @ViewBuilder private var background: some View {
        if opaqueBackground {
            Color(nsColor: .windowBackgroundColor)
        } else {
            VisualEffectBackground()
        }
    }

    private var header: some View {
        HStack {
            Text("Recent Screenshots")
                .font(.headline)
            Spacer()
            if let folder = model.folder {
                Label(folder.lastPathComponent, systemImage: "folder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help(folder.path)
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .loaded:
            grid
        case .empty:
            message(
                symbol: "photo.on.rectangle.angled",
                title: "No screenshots yet",
                detail: "macOS saves screenshots to \(model.folder?.lastPathComponent ?? "the Desktop"). Take one with ⇧⌘3 or ⇧⌘4 and it shows up here."
            )
        case .notAllowed:
            VStack(spacing: 12) {
                message(
                    symbol: "lock",
                    title: "Cutter may not read \(model.folder?.lastPathComponent ?? "the folder")",
                    detail: "Allow it under System Settings > Privacy & Security > Files and Folders > Cutter, then open this panel again."
                )
                Button("Open Privacy & Security…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                        NSWorkspace.shared.open(url)
                    }
                    model.perform(.close)
                }
            }
        case .failed(let reason):
            message(symbol: "exclamationmark.triangle", title: "Could not read the screenshots", detail: reason)
        }
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
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
                    spacing: 14
                ) {
                    ForEach(Array(model.screenshots.enumerated()), id: \.element) { index, screenshot in
                        ScreenshotCell(
                            screenshot: screenshot,
                            isSelected: model.selection == index,
                            thumbnails: thumbnails
                        )
                        .id(index)
                        .onTapGesture(count: 2) {
                            model.open(screenshot)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            model.selection = index
                        })
                        .onDrag {
                            model.dragBegan(at: index)
                            return NSItemProvider(contentsOf: screenshot.url) ?? NSItemProvider()
                        }
                        .contextMenu {
                            Button("Open") { model.open(screenshot) }
                            Button("Copy") { model.copy(screenshot) }
                            Button("Show in Finder") { model.reveal(screenshot) }
                        }
                    }
                }
                .padding(Self.padding)
            }
            .onChange(of: model.selection) { selection in
                if let selection {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(selection)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            hint("↩", "Open")
            hint("⌘C", "Copy")
            hint("⌘↩", "Show in Finder")
            hint("⎋", "Close")
            Spacer()
            if model.state == .loaded {
                Text(model.screenshots.count == ScreenshotBrowserModel.limit
                    ? "Newest \(ScreenshotBrowserModel.limit)"
                    : "\(model.screenshots.count) in all")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.footnote)
        .padding(.horizontal, Self.padding)
        .padding(.vertical, 9)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(keys)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text(label)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ScreenshotCell: View {
    let screenshot: Screenshot
    let isSelected: Bool
    let thumbnails: ThumbnailStore

    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05))
                if let image = image ?? thumbnails.cached(screenshot) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .padding(7)
                }
            }
            .frame(width: ScreenshotBrowserView.cellWidth, height: ScreenshotBrowserView.cellHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )

            Text(Self.caption(for: screenshot.date))
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onAppear(perform: loadThumbnail)
        .accessibilityLabel("Screenshot, \(Self.caption(for: screenshot.date))")
    }

    /// Reading and scaling a full-size screenshot takes a moment, so it happens off the
    /// main thread; the cell shows its placeholder until then.
    private func loadThumbnail() {
        guard image == nil else {
            return
        }
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

/// The translucent background macOS gives its own floating panels.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
