import AppKit
import CutterCore

// Draws the README's demo clip. Run it through scripts/make-demo.sh.
//
//   CutterDemo --gif docs/demo.gif [--mp4 demo.mp4] [--stills <directory>]
//
// Everything is drawn into off-screen bitmaps: no window opens and nothing is captured
// from the screen.

var gifPath: String?
var moviePath: String?
var stillsDirectory: String?

var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
    let option = arguments.removeFirst()
    guard !arguments.isEmpty else {
        fatalError("\(option) needs a path")
    }
    let value = arguments.removeFirst()
    switch option {
    case "--gif": gifPath = value
    case "--mp4": moviePath = value
    case "--stills": stillsDirectory = value
    default: fatalError("usage: CutterDemo --gif <file> [--mp4 <file>] [--stills <directory>]")
    }
}

let script = DemoScript()
let timeline = DemoTimeline(script: script)
guard !script.steps.isEmpty else {
    fatalError("None of the demo's actions has a default shortcut; there is nothing to show.")
}
if !script.loops {
    print("warning: the last step does not return the window to where the first step finds it, so the clip will jump when it repeats.")
}
for step in script.steps {
    let keys = SceneRenderer.keyLabels(for: step.shortcut).joined()
    print("\(keys)  \(step.action.title): \(Int(step.to.width))x\(Int(step.to.height)) at (\(Int(step.to.minX)), \(Int(step.to.minY)))")
}

func frame(at time: Double, scale: CGFloat) -> CGImage {
    SceneRenderer(layout: script.layout, scale: scale).image(for: timeline.moment(at: time)!)
}

func pixels(of image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(
        data: &bytes,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return bytes
}

if let gifPath {
    // GIF delays are whole hundredths of a second; 25 frames a second is 4 of them.
    let hundredthsPerFrame = 4
    let frameCount = Int((timeline.duration * 100 / Double(hundredthsPerFrame)).rounded())
    let times = (0..<frameCount).map { Double($0 * hundredthsPerFrame) / 100 }

    // The palette comes from frames spread over the clip, so every step has a say.
    let sampleTimes = stride(from: 0, to: timeline.duration, by: DemoTimeline.stepDuration / 6)
    var quantizer = ColorQuantizer(
        samples: sampleTimes.map { pixels(of: frame(at: $0, scale: 1)) },
        colorCount: 255,
        fixed: Wallpaper.colors + Palette.flatColors
    )

    let size = SceneRenderer(layout: script.layout, scale: 1).pixelSize
    var encoder = GIFEncoder(width: size.width, height: size.height, palette: quantizer.palette)
    for time in times {
        encoder.add(quantizer.indices(for: pixels(of: frame(at: time, scale: 1)), width: size.width), hundredths: hundredthsPerFrame)
    }
    let data = encoder.finish()
    try data.write(to: URL(fileURLWithPath: gifPath))
    print("Wrote \(gifPath): \(size.width)x\(size.height), \(String(format: "%.1f", timeline.duration)) s, \(data.count / 1024) KB")
}

if let moviePath {
    let framesPerSecond: Int32 = 30
    let size = SceneRenderer(layout: script.layout, scale: 2).pixelSize
    let movie = try MovieWriter(url: URL(fileURLWithPath: moviePath), width: size.width, height: size.height, framesPerSecond: framesPerSecond)
    let frameCount = Int((timeline.duration * Double(framesPerSecond)).rounded())
    for index in 0..<frameCount {
        try movie.append(frame(at: Double(index) / Double(framesPerSecond), scale: 2))
    }
    try movie.finish()
    print("Wrote \(moviePath): \(size.width)x\(size.height), \(String(format: "%.1f", timeline.duration)) s")
}

if let stillsDirectory {
    try FileManager.default.createDirectory(atPath: stillsDirectory, withIntermediateDirectories: true)
    // The middle of each move and the end of each step.
    for (index, _) in script.steps.enumerated() {
        let start = Double(index) * DemoTimeline.stepDuration
        for (name, offset) in [("moving", 0.75), ("settled", 1.6)] {
            let image = frame(at: start + offset, scale: 2)
            let bitmap = NSBitmapImageRep(cgImage: image)
            let path = "\(stillsDirectory)/step-\(index + 1)-\(name).png"
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }
    }
    print("Wrote stills to \(stillsDirectory)")
}
