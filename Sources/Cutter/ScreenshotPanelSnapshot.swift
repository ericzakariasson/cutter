#if DEBUG
import AppKit
import CutterCore
import SwiftUI

/// Draws the recent-screenshots panel into a PNG without showing it, filled with made-up
/// pictures in a temporary folder. No real screenshot is read. Debug builds only:
///
///     .build/debug/Cutter --snapshot-screenshots <file.png>
enum ScreenshotPanelSnapshot {
    static func run(to path: String?) -> Int32 {
        guard let path else {
            print("usage: Cutter --snapshot-screenshots <file.png>")
            return 2
        }
        _ = NSApplication.shared

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cutter-\(UUID().uuidString)")
            .appendingPathComponent("Desktop", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeSamples(to: folder)

            var environment = ScreenshotBrowserModel.Environment()
            environment.location = { (folder, nil) }
            environment.inBackground = { $0() }
            environment.onMain = { $0() }
            let model = ScreenshotBrowserModel(environment: environment)
            model.reload()

            // Thumbnails are made ahead, so the picture does not depend on timing.
            let thumbnails = ThumbnailStore()
            for screenshot in model.screenshots {
                _ = thumbnails.load(screenshot)
            }

            let view = NSHostingView(rootView: ScreenshotBrowserView(model: model, thumbnails: thumbnails, opaqueBackground: true))
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: ScreenshotBrowserView.size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))

            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: URL(fileURLWithPath: path))
            print("Wrote \(path): \(model.screenshots.count) sample pictures, \(bitmap.pixelsWide)x\(bitmap.pixelsHigh) pixels")
            return 0
        } catch {
            print("Failed: \(error.localizedDescription)")
            return 1
        }
    }

    // MARK: - Sample pictures

    private struct Sample {
        enum Kind {
            case desktop, window, strip, dialog
        }

        let kind: Kind
        let size: CGSize
        let hue: CGFloat
        let secondsAgo: TimeInterval
    }

    private static let samples: [Sample] = [
        Sample(kind: .window, size: CGSize(width: 1200, height: 800), hue: 0.60, secondsAgo: 2 * 60),
        Sample(kind: .strip, size: CGSize(width: 1400, height: 420), hue: 0.08, secondsAgo: 11 * 60),
        Sample(kind: .desktop, size: CGSize(width: 1728, height: 1117), hue: 0.72, secondsAgo: 38 * 60),
        Sample(kind: .dialog, size: CGSize(width: 640, height: 520), hue: 0.33, secondsAgo: 2 * 3600),
        Sample(kind: .window, size: CGSize(width: 900, height: 1100), hue: 0.92, secondsAgo: 3 * 3600),
        Sample(kind: .desktop, size: CGSize(width: 1728, height: 1117), hue: 0.52, secondsAgo: 5 * 3600),
        Sample(kind: .strip, size: CGSize(width: 1000, height: 260), hue: 0.45, secondsAgo: 26 * 3600),
        Sample(kind: .window, size: CGSize(width: 1280, height: 760), hue: 0.15, secondsAgo: 27 * 3600),
        Sample(kind: .dialog, size: CGSize(width: 520, height: 640), hue: 0.80, secondsAgo: 28 * 3600),
        Sample(kind: .desktop, size: CGSize(width: 3200, height: 1350), hue: 0.02, secondsAgo: 50 * 3600),
        Sample(kind: .window, size: CGSize(width: 1100, height: 820), hue: 0.40, secondsAgo: 74 * 3600),
        Sample(kind: .strip, size: CGSize(width: 1300, height: 360), hue: 0.66, secondsAgo: 75 * 3600),
        Sample(kind: .dialog, size: CGSize(width: 700, height: 460), hue: 0.25, secondsAgo: 98 * 3600),
        Sample(kind: .window, size: CGSize(width: 1240, height: 780), hue: 0.56, secondsAgo: 99 * 3600),
        Sample(kind: .desktop, size: CGSize(width: 1728, height: 1117), hue: 0.86, secondsAgo: 123 * 3600),
    ]

    private static func writeSamples(to folder: URL) throws {
        let now = Date()
        for (index, sample) in samples.enumerated() {
            let file = folder.appendingPathComponent("Sample \(index + 1).png")
            try png(for: sample).write(to: file)
            try ScreenshotFinder.markAsScreenCapture(file)
            let date = now.addingTimeInterval(-sample.secondsAgo)
            try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: file.path)
        }
        // Not screenshots; the panel must leave them out.
        try Data("notes".utf8).write(to: folder.appendingPathComponent("Notes.txt"))
        try png(for: samples[0]).write(to: folder.appendingPathComponent("Holiday photo.png"))
    }

    private static func png(for sample: Sample) throws -> Data {
        let width = Int(sample.size.width / 2)
        let height = Int(sample.size.height / 2)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }

        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let tint = NSColor(hue: sample.hue, saturation: 0.55, brightness: 0.85, alpha: 1)
        let deep = NSColor(hue: sample.hue + 0.08, saturation: 0.7, brightness: 0.45, alpha: 1)

        switch sample.kind {
        case .desktop:
            NSGradient(starting: tint, ending: deep)?.draw(in: bounds, angle: -60)
            NSColor.white.withAlphaComponent(0.25).setFill()
            NSRect(x: 0, y: bounds.maxY - 12, width: bounds.width, height: 12).fill()
            drawWindow(in: bounds.insetBy(dx: bounds.width * 0.18, dy: bounds.height * 0.16), accent: tint)
        case .window:
            drawWindow(in: bounds, accent: tint)
        case .strip:
            NSColor(white: 0.98, alpha: 1).setFill()
            bounds.fill()
            drawLines(in: bounds.insetBy(dx: 24, dy: 20), accent: tint, heading: false)
        case .dialog:
            NSColor(white: 0.95, alpha: 1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
            tint.setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.midX - 26, y: bounds.maxY - 84, width: 52, height: 52)).fill()
            drawLines(in: NSRect(x: 36, y: 70, width: bounds.width - 72, height: bounds.height - 180), accent: tint, heading: true)
            tint.setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.maxX - 130, y: 22, width: 100, height: 28), xRadius: 7, yRadius: 7).fill()
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    private static func drawWindow(in rect: NSRect, accent: NSColor) {
        let body = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSColor(white: 0.99, alpha: 1).setFill()
        body.fill()

        NSGraphicsContext.saveGraphicsState()
        body.addClip()
        NSColor(white: 0.92, alpha: 1).setFill()
        NSRect(x: rect.minX, y: rect.maxY - 26, width: rect.width, height: 26).fill()
        for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 10 + CGFloat(index) * 16, y: rect.maxY - 18, width: 10, height: 10)).fill()
        }
        let sidebarWidth = min(rect.width * 0.26, 150)
        NSColor(white: 0.95, alpha: 1).setFill()
        NSRect(x: rect.minX, y: rect.minY, width: sidebarWidth, height: rect.height - 26).fill()
        accent.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX + 8, y: rect.maxY - 60, width: sidebarWidth - 16, height: 18), xRadius: 5, yRadius: 5).fill()
        drawLines(
            in: NSRect(x: rect.minX + sidebarWidth + 20, y: rect.minY + 18, width: rect.width - sidebarWidth - 40, height: rect.height - 62),
            accent: accent,
            heading: true
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawLines(in rect: NSRect, accent: NSColor, heading: Bool) {
        var y = rect.maxY - 12
        if heading {
            NSColor(white: 0.25, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX, y: y, width: min(rect.width * 0.5, 220), height: 12), xRadius: 6, yRadius: 6).fill()
            y -= 30
        }
        let widths: [CGFloat] = [1, 0.92, 0.97, 0.6, 0, 0.95, 0.88, 1, 0.45]
        var index = 0
        while y > rect.minY {
            let fraction = widths[index % widths.count]
            if fraction > 0 {
                (index % widths.count == 3 ? accent.withAlphaComponent(0.6) : NSColor(white: 0.8, alpha: 1)).setFill()
                NSBezierPath(roundedRect: NSRect(x: rect.minX, y: y, width: rect.width * fraction, height: 7), xRadius: 3.5, yRadius: 3.5).fill()
            }
            y -= 16
            index += 1
        }
    }
}
#endif
