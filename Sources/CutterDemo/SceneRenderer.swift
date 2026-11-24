import AppKit
import CutterCore

/// Draws one frame of the demo clip into an off-screen bitmap: two displays with a
/// wallpaper and a menu bar, the window, and the keys of the current shortcut.
///
/// Sizes are in canvas points; `scale` turns them into pixels. The displays are drawn to
/// scale from the script's layout, so a window frame from `CutterCore` lands where it
/// would on the real arrangement. The window's chrome is drawn larger than life so that
/// it reads at this size.
struct SceneRenderer {
    static let canvasSize = CGSize(width: 720, height: 672)

    let layout: ScreenLayout
    let scale: CGFloat

    /// Canvas points per screen point.
    private static let displayScale: CGFloat = 0.2125
    private static let bezel: CGFloat = 6
    private static let topMargin: CGFloat = 26
    private static let gapBetweenDisplays: CGFloat = 14
    private static let keysCenterY: CGFloat = 630

    var pixelSize: (width: Int, height: Int) {
        (Int(Self.canvasSize.width * scale), Int(Self.canvasSize.height * scale))
    }

    func image(for moment: DemoTimeline.Moment) -> CGImage {
        let size = pixelSize
        let context = CGContext(
            data: nil,
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: size.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        // Top-left origin, like the app's window coordinates. Shadow offsets are not
        // affected by this and stay in the bitmap's own bottom-left coordinates.
        context.translateBy(x: 0, y: CGFloat(size.height))
        context.scaleBy(x: scale, y: -scale)

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.current = previous }

        draw(moment, in: context)
        return context.makeImage()!
    }

    // MARK: - Scene

    private func draw(_ moment: DemoTimeline.Moment, in context: CGContext) {
        context.setFillColor(Palette.canvas)
        context.fill(CGRect(origin: .zero, size: Self.canvasSize))

        for (index, screen) in layout.screens.enumerated() {
            let screenRect = canvasRect(of: screen.frame, onScreen: index)
            drawDisplay(screenRect, in: context)

            context.saveGState()
            context.addPath(CGPath(roundedRect: screenRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
            context.clip()
            drawWallpaper(in: screenRect, variant: index, context: context)
            // A window between two displays shows on each only the part that is on it.
            drawWindow(canvasRect(of: moment.windowFrame, onScreen: index), in: context)
            let menuBar = CGRect(
                x: screenRect.minX,
                y: screenRect.minY,
                width: screenRect.width,
                height: (screen.visibleFrame.minY - screen.frame.minY) * Self.displayScale
            )
            drawMenuBar(menuBar, in: context)
            // Whatever the visible area leaves free at the bottom belongs to the Dock.
            let dockHeight = (screen.frame.maxY - screen.visibleFrame.maxY) * Self.displayScale
            if dockHeight > 1 {
                drawDock(in: CGRect(x: screenRect.minX, y: screenRect.maxY - dockHeight, width: screenRect.width, height: dockHeight), context: context)
            }
            context.restoreGState()
        }

        drawKeys(for: moment, in: context)
    }

    /// Where a rectangle in screen coordinates falls on the canvas, for the display with
    /// the given index. Each display has its own spot on the canvas: on a desk there is a
    /// bezel between two screens that the coordinates know nothing about.
    private func canvasRect(of rect: CGRect, onScreen index: Int) -> CGRect {
        let screen = layout.screens[index].frame
        let origin = canvasOrigin(ofScreen: index)
        return CGRect(
            x: origin.x + (rect.minX - screen.minX) * Self.displayScale,
            y: origin.y + (rect.minY - screen.minY) * Self.displayScale,
            width: rect.width * Self.displayScale,
            height: rect.height * Self.displayScale
        )
    }

    /// Displays are stacked in the order of their rows, centred, with a gap for bezels.
    private func canvasOrigin(ofScreen index: Int) -> CGPoint {
        var y = Self.topMargin + Self.bezel
        for other in layout.displayOrder {
            let frame = layout.screens[other].frame
            if other == index {
                return CGPoint(x: ((Self.canvasSize.width - frame.width * Self.displayScale) / 2).rounded(), y: y.rounded())
            }
            y += frame.height * Self.displayScale + 2 * Self.bezel + Self.gapBetweenDisplays
        }
        return .zero
    }

    // MARK: - Displays

    private func drawDisplay(_ screenRect: CGRect, in context: CGContext) {
        let outer = screenRect.insetBy(dx: -Self.bezel, dy: -Self.bezel)
        let path = CGPath(roundedRect: outer, cornerWidth: 10, cornerHeight: 10, transform: nil)

        // No drop shadow: on the dark canvas it would only add grain to the GIF.
        context.addPath(path)
        context.setFillColor(Palette.bezel)
        context.fillPath()

        context.addPath(CGPath(roundedRect: outer.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 9.5, cornerHeight: 9.5, transform: nil))
        context.setStrokeColor(Palette.rgba(255, 255, 255, 0.14))
        context.setLineWidth(1)
        context.strokePath()
    }

    private func drawWallpaper(in rect: CGRect, variant: Int, context: CGContext) {
        // Drawn pixel for pixel, so that every pixel keeps one of the wallpaper's colours.
        let width = Int((rect.width * scale).rounded(.up)) + 1
        let height = Int((rect.height * scale).rounded(.up)) + 1
        let origin = CGPoint(x: (rect.minX * scale).rounded(.down) / scale, y: (rect.minY * scale).rounded(.down) / scale)
        context.interpolationQuality = .none
        context.draw(
            Wallpaper.image(variant: variant, width: width, height: height),
            in: CGRect(x: origin.x, y: origin.y, width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        )
        context.interpolationQuality = .default
    }

    private func drawMenuBar(_ rect: CGRect, in context: CGContext) {
        context.setFillColor(Palette.rgba(255, 255, 255, 0.2))
        context.fill(rect)

        let barHeight = rect.height * 0.3
        let y = rect.midY - barHeight / 2
        func bar(_ x: CGFloat, _ width: CGFloat, _ alpha: CGFloat = 0.92) {
            let pill = CGRect(x: x, y: y, width: width, height: barHeight)
            context.addPath(CGPath(roundedRect: pill, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
            context.setFillColor(Palette.rgba(255, 255, 255, alpha))
            context.fillPath()
        }

        // Left: the Apple menu and a few menu titles. Right: status items and the clock.
        var x = rect.minX + 6
        context.setFillColor(Palette.rgba(255, 255, 255, 0.95))
        context.fillEllipse(in: CGRect(x: x, y: rect.midY - barHeight * 0.8, width: barHeight * 1.6, height: barHeight * 1.6))
        x += barHeight * 1.6 + 5
        for width in [17, 9, 10, 11, 14] as [CGFloat] {
            bar(x, width)
            x += width + 5
        }

        var right = rect.maxX - 6
        for width in [16, 5, 5] as [CGFloat] {
            right -= width
            bar(right, width, 0.85)
            right -= 4
        }
        // Cutter's own menu bar icon: a window with its left half filled.
        let icon = CGRect(x: right - 6, y: rect.midY - barHeight * 0.95, width: 6, height: barHeight * 1.9)
        context.setFillColor(Palette.rgba(255, 255, 255, 0.45))
        context.fill(icon)
        context.setFillColor(Palette.rgba(255, 255, 255, 1))
        context.fill(CGRect(x: icon.minX, y: icon.minY, width: icon.width / 2, height: icon.height))
    }

    private func drawDock(in band: CGRect, context: CGContext) {
        let icons = Palette.dockIcons
        let iconSize = band.height * 0.58
        let gap = iconSize * 0.3
        let barHeight = band.height * 0.82
        let barWidth = CGFloat(icons.count) * iconSize + CGFloat(icons.count + 1) * gap
        let bar = CGRect(x: band.midX - barWidth / 2, y: band.maxY - barHeight - band.height * 0.09, width: barWidth, height: barHeight)
        let barPath = CGPath(roundedRect: bar, cornerWidth: barHeight * 0.3, cornerHeight: barHeight * 0.3, transform: nil)
        context.addPath(barPath)
        context.setFillColor(Palette.rgba(255, 255, 255, 0.32))
        context.fillPath()
        context.addPath(barPath)
        context.setStrokeColor(Palette.rgba(255, 255, 255, 0.35))
        context.setLineWidth(0.5)
        context.strokePath()

        var x = bar.minX + gap
        for color in icons {
            let icon = CGRect(x: x, y: bar.midY - iconSize / 2, width: iconSize, height: iconSize)
            context.addPath(CGPath(roundedRect: icon, cornerWidth: iconSize * 0.24, cornerHeight: iconSize * 0.24, transform: nil))
            context.setFillColor(color)
            context.fillPath()
            x += iconSize + gap
        }
    }

    // MARK: - Window

    private func drawWindow(_ rect: CGRect, in context: CGContext) {
        let radius: CGFloat = 7
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -5 * scale), blur: 14 * scale, color: Palette.rgba(0, 0, 0, 0.45))
        context.addPath(path)
        context.setFillColor(Palette.windowBody)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.clip()

        let titleBarHeight: CGFloat = 22
        let titleBar = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: titleBarHeight)
        context.setFillColor(Palette.titleBar)
        context.fill(titleBar)
        context.setFillColor(Palette.hairline)
        context.fill(CGRect(x: rect.minX, y: titleBar.maxY - 0.5, width: rect.width, height: 0.5))

        for (index, color) in [Palette.close, Palette.minimize, Palette.zoom].enumerated() {
            let center = CGPoint(x: rect.minX + 13 + CGFloat(index) * 13, y: titleBar.midY)
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
        }

        let title = NSAttributedString(string: "Notes", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor(cgColor: Palette.titleText)!,
        ])
        let titleSize = title.size()
        if rect.width > 150 {
            title.draw(at: CGPoint(x: rect.midX - titleSize.width / 2, y: titleBar.midY - titleSize.height / 2))
        }

        // A sidebar with a selected row, and a page of text.
        let sidebarWidth = min(max(rect.width * 0.24, 58), 132)
        let sidebar = CGRect(x: rect.minX, y: titleBar.maxY, width: sidebarWidth, height: rect.height - titleBarHeight)
        context.setFillColor(Palette.sidebar)
        context.fill(sidebar)
        context.setFillColor(Palette.hairline)
        context.fill(CGRect(x: sidebar.maxX - 0.5, y: sidebar.minY, width: 0.5, height: sidebar.height))

        var rowY = sidebar.minY + 9
        var row = 0
        while rowY + 14 < sidebar.maxY, row < 9 {
            let rowRect = CGRect(x: sidebar.minX + 6, y: rowY, width: sidebar.width - 12, height: 14)
            if row == 1 {
                context.addPath(CGPath(roundedRect: rowRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
                context.setFillColor(Palette.accent)
                context.fillPath()
            }
            let widths: [CGFloat] = [0.62, 0.8, 0.5, 0.7, 0.56, 0.74, 0.45, 0.66, 0.58]
            let line = CGRect(x: rowRect.minX + 6, y: rowRect.midY - 2, width: (rowRect.width - 12) * widths[row], height: 4)
            context.addPath(CGPath(roundedRect: line, cornerWidth: 2, cornerHeight: 2, transform: nil))
            context.setFillColor(row == 1 ? Palette.rgba(255, 255, 255, 0.95) : Palette.placeholder)
            context.fillPath()
            rowY += 18
            row += 1
        }

        let content = CGRect(
            x: sidebar.maxX + 16,
            y: titleBar.maxY + 16,
            width: rect.maxX - sidebar.maxX - 32,
            height: rect.maxY - titleBar.maxY - 28
        )
        if content.width > 24, content.height > 12 {
            let heading = CGRect(x: content.minX, y: content.minY, width: min(content.width * 0.55, 170), height: 9)
            context.addPath(CGPath(roundedRect: heading, cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
            context.setFillColor(Palette.heading)
            context.fillPath()

            let lineWidths: [CGFloat] = [1, 0.94, 0.98, 0.62, 0, 0.96, 0.9, 1, 0.86, 0.4, 0, 0.97, 0.93, 0.7]
            var lineY = content.minY + 24
            var index = 0
            while lineY + 5 <= content.maxY {
                let fraction = lineWidths[index % lineWidths.count]
                if fraction > 0 {
                    let line = CGRect(x: content.minX, y: lineY, width: min(content.width, 420) * fraction, height: 5)
                    context.addPath(CGPath(roundedRect: line, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
                    context.setFillColor(Palette.placeholder)
                    context.fillPath()
                }
                lineY += 12
                index += 1
            }
        }
        context.restoreGState()

        context.addPath(path)
        context.setStrokeColor(Palette.rgba(0, 0, 0, 0.28))
        context.setLineWidth(0.5)
        context.strokePath()
    }

    // MARK: - Keys

    /// The shortcut as Settings shows it, one key cap per key, followed by the action.
    private func drawKeys(for moment: DemoTimeline.Moment, in context: CGContext) {
        guard moment.keysOpacity > 0 else {
            return
        }
        let labels = Self.keyLabels(for: moment.step.shortcut)
        let title = NSAttributedString(string: moment.step.action.title, attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor(white: 1, alpha: 0.94),
        ])
        let titleSize = title.size()

        let capSize: CGFloat = 38
        let capGap: CGFloat = 8
        let titleGap: CGFloat = 16
        let capsWidth = CGFloat(labels.count) * capSize + CGFloat(labels.count - 1) * capGap
        var x = (Self.canvasSize.width - (capsWidth + titleGap + titleSize.width)) / 2
        let top = Self.keysCenterY - capSize / 2

        context.saveGState()
        context.setAlpha(moment.keysOpacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        for label in labels {
            drawKeyCap(label, in: CGRect(x: x, y: top, width: capSize, height: capSize), pressed: moment.keysPressed, context: context)
            x += capSize + capGap
        }
        title.draw(at: CGPoint(x: x - capGap + titleGap, y: Self.keysCenterY - titleSize.height / 2))
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawKeyCap(_ label: String, in rect: CGRect, pressed: Double, context: CGContext) {
        let travel: CGFloat = 3
        let depth = travel * CGFloat(1 - pressed)

        // The side of the key, showing less of itself as the key goes down.
        let base = CGPath(roundedRect: rect, cornerWidth: 9, cornerHeight: 9, transform: nil)
        context.addPath(base)
        context.setFillColor(Palette.keySide)
        context.fillPath()

        let face = CGRect(x: rect.minX, y: rect.minY + (travel - depth), width: rect.width, height: rect.height - travel)
        let facePath = CGPath(roundedRect: face, cornerWidth: 9, cornerHeight: 9, transform: nil)
        context.saveGState()
        context.addPath(facePath)
        context.clip()
        let shade = CGFloat(pressed) * 0.08
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [Palette.gray(0.995 - shade), Palette.gray(0.9 - shade)] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(gradient, start: CGPoint(x: face.midX, y: face.minY), end: CGPoint(x: face.midX, y: face.maxY), options: [])
        context.restoreGState()

        let text = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: label.count > 1 ? 11 : 19, weight: .medium),
            .foregroundColor: NSColor(cgColor: Palette.keyText)!,
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: face.midX - size.width / 2, y: face.midY - size.height / 2))
    }

    /// One label per key, modifiers first, in the glyphs Settings and the recorder use.
    static func keyLabels(for shortcut: KeyCombo) -> [String] {
        let modifiers: [KeyCombo.Modifiers] = [.control, .option, .shift, .command]
        let held = modifiers.filter { shortcut.modifiers.contains($0) }.map(\.symbols)
        return held + [KeyCode.specialKeyName(for: shortcut.keyCode) ?? "Key \(shortcut.keyCode)"]
    }
}

/// The desktop picture: soft bands of colour that bend across the screen, in the manner
/// of the macOS wallpapers.
///
/// Every pixel takes one of a fixed run of colours. A GIF holds 256 colours in all, and a
/// free two-dimensional gradient would need far more and come out blotchy. With the run
/// fixed, the encoder can keep exactly these colours and the bands stay too fine to see.
enum Wallpaper {
    /// The colours from one end of the wallpaper to the other.
    static let colors: [RGB] = {
        let stops: [(position: Double, red: Double, green: Double, blue: Double)] = [
            (0, 14, 30, 92),
            (0.3, 34, 78, 190),
            (0.55, 104, 84, 208),
            (0.8, 206, 98, 158),
            (1, 250, 156, 112),
        ]
        let count = 100
        return (0..<count).map { index in
            let position = Double(index) / Double(count - 1)
            let upper = stops.firstIndex { $0.position >= position } ?? stops.count - 1
            let lower = max(upper - 1, 0)
            let span = stops[upper].position - stops[lower].position
            let t = span > 0 ? (position - stops[lower].position) / span : 0
            func mix(_ a: Double, _ b: Double) -> UInt8 {
                UInt8((a + (b - a) * t).rounded())
            }
            return RGB(
                red: mix(stops[lower].red, stops[upper].red),
                green: mix(stops[lower].green, stops[upper].green),
                blue: mix(stops[lower].blue, stops[upper].blue)
            )
        }
    }()

    private static var cache: [String: CGImage] = [:]

    static func image(variant: Int, width: Int, height: Int) -> CGImage {
        let key = "\(variant)-\(width)x\(height)"
        if let cached = cache[key] {
            return cached
        }
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let phase = Double(variant) * 2.1
        for y in 0..<height {
            for x in 0..<width {
                // Both measured against the width, so the pattern is not stretched.
                let u = Double(x) / Double(width)
                let v = Double(y) / Double(width)
                var value = 0.08 + 0.62 * u + 0.75 * v
                value += 0.11 * sin(2 * .pi * (0.9 * u - 1.3 * v) + 0.8 + phase)
                value += 0.05 * sin(2 * .pi * (2.1 * u + 1.6 * v) + 2.4 - phase)
                let color = colors[min(max(Int(value * Double(colors.count)), 0), colors.count - 1)]
                let offset = (y * width + x) * 4
                bytes[offset] = color.red
                bytes[offset + 1] = color.green
                bytes[offset + 2] = color.blue
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        cache[key] = image
        return image
    }
}

/// The clip's colours.
enum Palette {
    static func rgba(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat) -> CGColor {
        CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }

    static func gray(_ white: CGFloat) -> CGColor {
        CGColor(srgbRed: white, green: white, blue: white, alpha: 1)
    }

    static let canvas = rgba(17, 19, 24, 1)
    static let bezel = rgba(8, 8, 10, 1)
    static let windowBody = rgba(252, 252, 253, 1)
    static let titleBar = rgba(236, 236, 239, 1)
    static let titleText = rgba(70, 70, 76, 1)
    static let sidebar = rgba(242, 242, 245, 1)
    static let hairline = rgba(206, 206, 212, 1)
    static let placeholder = rgba(205, 206, 212, 1)
    static let heading = rgba(58, 58, 64, 1)
    static let accent = rgba(10, 132, 255, 1)
    static let close = rgba(255, 95, 87, 1)
    static let minimize = rgba(254, 188, 46, 1)
    static let zoom = rgba(40, 200, 64, 1)
    static let keySide = rgba(150, 152, 162, 1)
    static let keyText = rgba(34, 34, 38, 1)
    static let dockIcons = [
        rgba(64, 156, 255, 1), rgba(250, 250, 252, 1), rgba(52, 199, 89, 1), rgba(255, 159, 10, 1),
        rgba(255, 69, 58, 1), rgba(175, 82, 222, 1), rgba(100, 210, 255, 1), rgba(255, 214, 10, 1), rgba(142, 142, 147, 1),
    ]

    /// The flat colours that cover whole areas. The GIF keeps these exactly, so that the
    /// areas stay flat instead of being dithered.
    static let flatColors: [RGB] = ([canvas, bezel, windowBody, titleBar, sidebar, hairline, placeholder, heading, accent, keySide] + dockIcons).map { color in
        let parts = color.components ?? [0, 0, 0, 1]
        return RGB(red: UInt8((parts[0] * 255).rounded()), green: UInt8((parts[1] * 255).rounded()), blue: UInt8((parts[2] * 255).rounded()))
    }
}
