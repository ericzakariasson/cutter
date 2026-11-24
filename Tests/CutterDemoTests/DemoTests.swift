import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import CutterDemo
import CutterCore

@Suite struct DemoScriptTests {
    let script = DemoScript()

    @Test func showsTheFiveDefaultShortcutsInOrder() {
        #expect(script.steps.map(\.action) == [.leftHalf, .rightHalf, .maximize, .previousDisplay, .nextDisplay])
        let defaults = ShortcutConfiguration.defaultShortcuts
        for step in script.steps {
            #expect(step.shortcut == defaults[step.action])
        }
    }

    @Test func showsTheKeysAsSettingsDoes() {
        let labels = script.steps.map { SceneRenderer.keyLabels(for: $0.shortcut) }
        #expect(labels == [["⌃", "⌥", "←"], ["⌃", "⌥", "→"], ["⌃", "⌥", "↩"], ["⌃", "⌥", "↑"], ["⌃", "⌥", "↓"]])
    }

    @Test func everyStepStartsWhereTheOneBeforeEnded() {
        for (before, after) in zip(script.steps, script.steps.dropFirst()) {
            #expect(before.to == after.from)
        }
    }

    @Test func theClipEndsWhereItStarts() {
        #expect(script.loops)
        #expect(script.steps.first?.from == script.steps.last?.to)
    }

    /// The frames are the app's own: a placement is that part of the visible area of the
    /// screen the window is on, and the display moves follow the display order.
    @Test func theFramesAreWhatTheAppWouldProduce() throws {
        let laptop = script.layout.screens[0].visibleFrame
        let above = script.layout.screens[1].visibleFrame
        #expect(script.layout.displayOrder == [1, 0])

        let frames = script.steps.map(\.to)
        #expect(frames[0] == CGRect(x: laptop.minX, y: laptop.minY, width: laptop.width / 2, height: laptop.height))
        #expect(frames[1] == CGRect(x: laptop.midX, y: laptop.minY, width: laptop.width / 2, height: laptop.height))
        #expect(frames[2] == laptop)
        // ↑ is "previous display": from the laptop that is the display above it.
        #expect(frames[3] == above)
        // ↓ is "next display": back down, still maximized.
        #expect(frames[4] == laptop)
    }

    @Test func theWindowIsAlwaysInsideAVisibleArea() {
        for step in script.steps {
            let inside = script.layout.screens.contains { $0.visibleFrame.contains(step.to) }
            #expect(inside)
        }
    }

    @Test func anActionWithoutADefaultShortcutIsLeftOut() {
        var configuration = ShortcutConfiguration()
        configuration.setShortcut(nil, for: .rightHalf)
        let shorter = DemoScript(configuration: configuration)
        #expect(shorter.steps.map(\.action) == [.leftHalf, .maximize, .previousDisplay, .nextDisplay])
    }

    @Test func aChangedShortcutShowsItsNewKeys() {
        var configuration = ShortcutConfiguration()
        configuration.setShortcut(KeyCombo(keyCode: KeyCode.upArrow, modifiers: [.command, .shift]), for: .maximize)
        let changed = DemoScript(configuration: configuration)
        // ⌃⌥↑ is free again, so "previous display" keeps its default; maximize shows ⇧⌘↑.
        let maximize = changed.steps.first { $0.action == .maximize }
        #expect(maximize.map { SceneRenderer.keyLabels(for: $0.shortcut) } == ["⇧", "⌘", "↑"])
    }
}

@Suite struct DemoTimelineTests {
    let timeline = DemoTimeline(script: DemoScript())

    @Test func lastsBetweenTenAndFifteenSeconds() {
        #expect(timeline.duration >= 10)
        #expect(timeline.duration <= 15)
    }

    @Test func eachStepStartsAndEndsOnItsFrames() throws {
        for (index, step) in timeline.script.steps.enumerated() {
            let start = Double(index) * DemoTimeline.stepDuration
            #expect(try #require(timeline.moment(at: start)).windowFrame == step.from)
            #expect(try #require(timeline.moment(at: start + DemoTimeline.stepDuration - 0.01)).windowFrame == step.to)
        }
    }

    @Test func theKeysAreGoneWhereTheClipRepeats() throws {
        #expect(try #require(timeline.moment(at: 0)).keysOpacity == 0)
        #expect(try #require(timeline.moment(at: timeline.duration - 0.001)).keysOpacity < 0.01)
        // The first frame and the frame after the last one are the same picture.
        let first = try #require(timeline.moment(at: 0))
        let wrapped = try #require(timeline.moment(at: timeline.duration))
        #expect(first.windowFrame == wrapped.windowFrame)
    }

    @Test func theKeysAreDownWhileTheWindowStartsToMove() throws {
        let moment = try #require(timeline.moment(at: 0.55))
        #expect(moment.keysOpacity == 1)
        #expect(moment.keysPressed == 1)
    }
}

@Suite struct GIFEncoderTests {
    private let palette = [
        RGB(red: 0, green: 0, blue: 0),
        RGB(red: 255, green: 0, blue: 0),
        RGB(red: 0, green: 200, blue: 90),
        RGB(red: 250, green: 250, blue: 252),
    ]

    /// A frame of `width` by `height` filled with one colour, with a block of another.
    private func frame(width: Int, height: Int, background: UInt8, block: UInt8, at origin: (x: Int, y: Int)) -> [UInt8] {
        var pixels = [UInt8](repeating: background, count: width * height)
        for y in origin.y..<min(origin.y + 5, height) {
            for x in origin.x..<min(origin.x + 7, width) {
                pixels[y * width + x] = block
            }
        }
        return pixels
    }

    private func decode(_ data: Data) throws -> (frames: [[RGB]], delays: [Double], loopCount: Int?) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        var frames: [[RGB]] = []
        var delays: [Double] = []
        for index in 0..<CGImageSourceGetCount(source) {
            let image = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = try #require(CGContext(
                data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            frames.append(stride(from: 0, to: bytes.count, by: 4).map { RGB(red: bytes[$0], green: bytes[$0 + 1], blue: bytes[$0 + 2]) })

            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            delays.append(gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double ?? 0)
        }
        let fileProperties = CGImageSourceCopyProperties(source, nil) as? [String: Any]
        let loopCount = (fileProperties?[kCGImagePropertyGIFDictionary as String] as? [String: Any])?[kCGImagePropertyGIFLoopCount as String] as? Int
        return (frames, delays, loopCount)
    }

    /// The file is read back with ImageIO, the decoder macOS itself uses.
    @Test func framesComeBackAsTheyWentIn() throws {
        let width = 64, height = 48
        let frames = [
            frame(width: width, height: height, background: 0, block: 1, at: (2, 3)),
            frame(width: width, height: height, background: 0, block: 1, at: (20, 10)),
            frame(width: width, height: height, background: 0, block: 2, at: (50, 40)),
            frame(width: width, height: height, background: 3, block: 2, at: (0, 0)),
        ]
        var encoder = GIFEncoder(width: width, height: height, palette: palette)
        for pixels in frames {
            encoder.add(pixels, hundredths: 4)
        }
        let decoded = try decode(encoder.finish())

        #expect(decoded.frames.count == frames.count)
        for (pixels, image) in zip(frames, decoded.frames) {
            #expect(image == pixels.map { palette[Int($0)] })
        }
        #expect(decoded.delays.allSatisfy { abs($0 - 0.04) < 0.0001 })
        #expect(decoded.loopCount == 0)
    }

    @Test func aFrameThatDoesNotChangeExtendsTheOneBefore() throws {
        let width = 32, height = 32
        let still = frame(width: width, height: height, background: 0, block: 1, at: (4, 4))
        let moved = frame(width: width, height: height, background: 0, block: 1, at: (12, 4))
        var encoder = GIFEncoder(width: width, height: height, palette: palette)
        for _ in 0..<10 {
            encoder.add(still, hundredths: 4)
        }
        encoder.add(moved, hundredths: 4)
        let decoded = try decode(encoder.finish())

        #expect(decoded.frames.count == 2)
        #expect(abs(decoded.delays[0] - 0.4) < 0.0001)
        #expect(abs(decoded.delays[1] - 0.04) < 0.0001)
        #expect(decoded.frames[1] == moved.map { palette[Int($0)] })
    }

    /// A busy frame fills the compressor's table several times over.
    @Test func aLargeNoisyFrameSurvives() throws {
        let width = 200, height = 150
        var state: UInt32 = 12345
        var pixels = [UInt8](repeating: 0, count: width * height)
        for index in pixels.indices {
            state = state &* 1_664_525 &+ 1_013_904_223
            pixels[index] = UInt8((state >> 24) % 4)
        }
        var encoder = GIFEncoder(width: width, height: height, palette: palette)
        encoder.add(pixels, hundredths: 10)
        let decoded = try decode(encoder.finish())
        #expect(decoded.frames.count == 1)
        #expect(decoded.frames[0] == pixels.map { palette[Int($0)] })
    }
}

@Suite struct ColorQuantizerTests {
    @Test func fixedColorsKeepTheirPlaceAndAreMatchedExactly() {
        let fixed = [RGB(red: 10, green: 20, blue: 30), RGB(red: 12, green: 20, blue: 30), RGB(red: 250, green: 250, blue: 252)]
        // Two fixed colours that differ by two levels, and some other colours.
        var sample: [UInt8] = []
        for color in fixed + [RGB(red: 200, green: 0, blue: 0), RGB(red: 0, green: 0, blue: 200)] {
            for _ in 0..<50 {
                sample += [color.red, color.green, color.blue, 255]
            }
        }
        var quantizer = ColorQuantizer(samples: [sample], colorCount: 16, fixed: fixed)
        #expect(Array(quantizer.palette.prefix(3)) == fixed)
        #expect(quantizer.palette.count <= 16)

        let indices = quantizer.indices(for: sample, width: 50)
        #expect(indices[0] == 0)
        #expect(indices[50] == 1)
        #expect(indices[100] == 2)
        #expect(quantizer.palette[Int(indices[150])] == RGB(red: 200, green: 0, blue: 0))
    }

    @Test func theWallpaperAndFlatColorsLeaveRoomInThePalette() {
        let fixed = Wallpaper.colors + Palette.flatColors
        #expect(Set(fixed).count == fixed.count)
        #expect(fixed.count <= 160)
    }
}

@Suite struct SceneRendererTests {
    @Test func drawsAFrameOfTheExpectedSize() throws {
        let script = DemoScript()
        let moment = try #require(DemoTimeline(script: script).moment(at: 1.6))
        let image = SceneRenderer(layout: script.layout, scale: 1).image(for: moment)
        #expect(image.width == 720)
        #expect(image.height == 672)
        // Even sizes, as H.264 needs, at the movie's scale too.
        let movie = SceneRenderer(layout: script.layout, scale: 2).pixelSize
        #expect(movie.width % 2 == 0)
        #expect(movie.height % 2 == 0)
    }
}
