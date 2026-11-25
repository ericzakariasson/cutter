import AppKit

/// The surface of the screenshots panel: one sheet of the system's Liquid Glass on
/// macOS 26, and the standard blurred material on earlier systems.
///
/// The panel's window is borderless and transparent, so this view alone gives the panel
/// its shape. It keeps a clear margin around the sheet: room for the shadow, which a
/// sheet filling the window to its edges would have cut off.
final class ScreenshotPanelSurface: NSView {
    /// The clear room around the sheet, on every side.
    static let margin: CGFloat = 36

    /// macOS 26 gives windows and floating panels much rounder corners than before.
    static var cornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 26
        }
        return 16
    }

    /// Called for a click in the clear margin, which is a click beside the panel.
    var onClickBeside: (() -> Void)?

    /// The glass or blur itself.
    let sheet: NSView

    init(content: NSView, contentSize: CGSize) {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = content
            sheet = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .popover
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.maskImage = Self.roundedMask(radius: Self.cornerRadius)
            blur.addSubview(content)
            sheet = blur
        }
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: contentSize.width + 2 * Self.margin,
            height: contentSize.height + 2 * Self.margin
        ))

        sheet.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sheet)
        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.margin),
            sheet.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.margin),
            sheet.topAnchor.constraint(equalTo: topAnchor, constant: Self.margin),
            sheet.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.margin),
            content.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            content.topAnchor.constraint(equalTo: sheet.topAnchor),
            content.bottomAnchor.constraint(equalTo: sheet.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    /// Only clicks in the margin arrive here; the sheet takes its own.
    override func mouseDown(with event: NSEvent) {
        onClickBeside?()
    }

    /// A stretchable image that is opaque inside a rounded rectangle: the shape the
    /// blurred material is cut to.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
