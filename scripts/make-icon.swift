// Draws Cutter's app icon and writes Support/AppIcon.icns.
//
//   swift scripts/make-icon.swift
//
// The result is checked in, so this only needs to run when the design changes.
import AppKit
import Foundation

/// Draws the icon into a square of `size` pixels: a screen-coloured tile holding a window
/// cut into a solid left half and a faint right half.
func drawIcon(size: CGFloat, in context: CGContext) {
    let unit = size / 1024
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // macOS icons sit in an 824-point rounded square inside the 1024-point canvas.
    let tile = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185 * unit, cornerHeight: 185 * unit, transform: nil)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -10 * unit),
        blur: 24 * unit,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3)
    )
    context.addPath(tilePath)
    context.setFillColor(CGColor(red: 0.16, green: 0.2, blue: 0.5, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.36, green: 0.47, blue: 0.98, alpha: 1),
            CGColor(red: 0.2, green: 0.22, blue: 0.62, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: tile.midX, y: tile.maxY),
        end: CGPoint(x: tile.midX, y: tile.minY),
        options: []
    )
    context.restoreGState()

    let window = CGRect(x: 232 * unit, y: 312 * unit, width: 560 * unit, height: 400 * unit)
    let gap = 20 * unit
    let radius = 44 * unit
    let halfWidth = (window.width - gap) / 2
    let left = CGRect(x: window.minX, y: window.minY, width: halfWidth, height: window.height)
    let right = CGRect(x: window.maxX - halfWidth, y: window.minY, width: halfWidth, height: window.height)

    context.addPath(CGPath(roundedRect: left, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fillPath()

    context.addPath(CGPath(roundedRect: right, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.32))
    context.fillPath()
}

func pngData(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    drawIcon(size: CGFloat(pixels), in: graphics.cgContext)
    return bitmap.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("Support/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Cutter-\(UUID().uuidString)")
    .appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset.deletingLastPathComponent()) }

for points in [16, 32, 128, 256, 512] {
    try pngData(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try pngData(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed")
}

if let preview = CommandLine.arguments.dropFirst().first {
    try pngData(pixels: 512).write(to: URL(fileURLWithPath: preview))
}
print("Wrote \(output.path)")
